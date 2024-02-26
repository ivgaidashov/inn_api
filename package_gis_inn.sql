CREATE OR REPLACE PACKAGE gis_inn AS
  v_queue_name CONSTANT VARCHAR2(20) := 'xxi.gis_inn_queue';

  /*список документов, по которым можно получить ИНН*/
  TYPE inn_doc_aat IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(5);

  /*серия и номер документа*/
  TYPE t_doc_info IS RECORD
  (
       cpassportseries VARCHAR2(30),
       cpassportnumber VARCHAR2(30)
  );

  /*сохранённые операционистом документы, по которым можно найти ИНН*/
  TYPE t_saved_docs_tab IS TABLE OF t_doc_info INDEX BY VARCHAR2(5);

  FUNCTION f_is_doc_typ_valid (p_doctype VARCHAR2) RETURN NUMBER;

  PROCEDURE p_send_req(p_person_info IN INN_MSG_TYPE, p_status OUT VARCHAR2, p_err_mess OUT VARCHAR2);

  PROCEDURE p_get_response (p_requestid IN VARCHAR2, p_status OUT VARCHAR2, p_value OUT VARCHAR2);
END gis_inn;
/
CREATE OR REPLACE PACKAGE BODY gis_inn IS

  FUNCTION f_is_doc_typ_valid(p_doctype VARCHAR2) RETURN NUMBER IS
    l_inn_doc_types inn_doc_aat;
    i               VARCHAR2(5);
    v_res           NUMBER := 0;

  BEGIN
    l_inn_doc_types('01') := 'Паспорт гражданина СССР';
    l_inn_doc_types('03') := 'Свидетельство о рождении';
    l_inn_doc_types('10') := 'Паспорт иностранного гражданина';
    l_inn_doc_types('12') := 'Вид на жительство в Российской Федерации';
    l_inn_doc_types('15') := 'Разрешение на временное проживание в Российской Федерации';
    l_inn_doc_types('16') := 'Временное удостоверение личности лица без гражданства в РФ';
    l_inn_doc_types('19') := 'Свидетельство о предоставлении временного убежища на территории Российской Федерации';
    l_inn_doc_types('21') := 'Паспорт гражданина Российской Федерации';
    l_inn_doc_types('22') := 'Загранпаспорт гражданина Российской Федерации';
    l_inn_doc_types('23') := 'Свидетельство о рождении, выданное уполномоченным органом иностранного государства';

    i := l_inn_doc_types.first;
    LOOP
      EXIT WHEN i IS NULL;

      IF i = p_doctype THEN
        v_res := 1;
        EXIT;
      END IF;
      i := l_inn_doc_types.NEXT(i);
    END LOOP;
    RETURN v_res;

  END;

  PROCEDURE p_send_req(p_person_info IN INN_MSG_TYPE, p_status OUT VARCHAR2 /*0-успешно,1-ошибка*/, p_err_mess OUT VARCHAR2) IS PRAGMA AUTONOMOUS_TRANSACTION;
    l_enqueue_options    DBMS_AQ.enqueue_options_t;
    l_message_properties DBMS_AQ.message_properties_t;
    l_message_handle     RAW(16);

  BEGIN

    DBMS_AQ.enqueue(queue_name         => v_queue_name,
                    enqueue_options    => l_enqueue_options,
                    message_properties => l_message_properties,
                    payload            => p_person_info,
                    msgid              => l_message_handle);

    COMMIT;
    p_status := '0';
    p_err_mess :='';
    EXCEPTION
    WHEN OTHERS THEN
      p_status := '1';
      p_err_mess :=to_char(SQLCODE) || ' ' || to_char(SQLERRM);
  END;

  PROCEDURE p_get_response (p_requestid IN VARCHAR2, p_status OUT VARCHAR2 /*Success или Error*/, p_value OUT VARCHAR2) IS
    v_status gis_inn_responses.cstatus%TYPE;
    v_value  gis_inn_responses.cvalue%TYPE;
    v_loop_cnt             INTEGER := 0;

    BEGIN
      WHILE v_status IS NULL
        LOOP

          BEGIN
            SELECT CSTATUS, CVALUE INTO v_status, v_value FROM gis_inn_responses WHERE crequestid = p_requestid;
          EXCEPTION WHEN no_data_found THEN
            dbms_output.put_line('no data found.');
          END;

          IF v_status IS NOT NULL THEN
            p_status := v_status;
            p_value  := v_value;
          END IF;

          IF v_loop_cnt = 10 THEN
            v_status := 'No results';
            p_status := 'No results';
          END IF;

          v_loop_cnt := v_loop_cnt + 1;
          DBMS_LOCK.sleep(1); -- sleep for 1 second
        END LOOP;
    END;
END;
/
