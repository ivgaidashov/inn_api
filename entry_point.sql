declare
  l_rcus            account2.cus_type;        /*введенные данные клиента*/
  v_DCM_TAB         account2.t_dcm;           /*введенные ДУЛ*/
  v_new_doc         gis_inn.t_doc_info;       /*тип строки: серия и номер ДУЛа*/
  t_saved_docs_aat  gis_inn.t_saved_docs_tab; /*коллекция введенных ДУЛов, по которым можно найти ИНН*/
  
  v_person         inn_msg_type;              /*данные клиента на отправку в функцию запроса ИНН*/
  v_cnt            PLS_INTEGER;
  v_inn_doc_type   VARCHAR2(5);
  v_is_valid       PLS_INTEGER;
  v_birthday       VARCHAR2(10);
  i                VARCHAR2(5);
  v_uuid           VARCHAR2(36);
  v_status_send    VARCHAR2(15);
  v_err_msg_send   VARCHAR2(150);
  v_status_resp    VARCHAR2(15);
  v_err_msg_resp   gis_inn_responses.cvalue%type;
  
  CURSOR cPUD(cs_id in number) is
    select CPUDCODE3
      from PUD
     where ipuduse < 1
       and ipudid = cs_id;

BEGIN
  /*получаем данные клиента*/
  account2.get_cus_record(l_rcus);
  /*получаем введенные документы клиента*/
  account2.get_dcm_table(v_DCM_TAB);

  v_cnt := v_DCM_TAB.count;
  IF v_cnt > 0 AND l_rcus.CCUSFLAG in ('1', '4') AND l_rcus.ccusnumnal IS NULL /*если введены док-ты, это ФЛ или ИП, ИНН пусто*/ THEN
    FOR i in v_DCM_TAB.first .. v_DCM_TAB.last LOOP
      OPEN cPUD(v_DCM_TAB(i).id_doc_tp);
      FETCH cPUD INTO v_inn_doc_type;
      CLOSE cPUD;
      
      /*можно ли по данному документы получить ИНН*/
      v_is_valid := gis_inn.f_is_doc_typ_valid(v_inn_doc_type);
    
      IF v_is_valid = 1 THEN
        /*для паспорта РФ убеждаемся, что есть пробел в серии, это требование API*/
        IF v_inn_doc_type = '21' THEN
          v_new_doc.cpassportseries := REGEXP_REPLACE(v_DCM_TAB(i).doc_ser, '(^\d{2})(\d{2}$)', '\1 \2');
        ELSE
          v_new_doc.cpassportseries := v_DCM_TAB(i).doc_ser;
        END IF;
        v_new_doc.cpassportnumber := v_DCM_TAB(i).doc_num;
        
        /*сохраняем документы в отдельную коллекцию*/
        t_saved_docs_aat(v_inn_doc_type) := v_new_doc;
      END IF;
    
    END LOOP;
    
    /*переводим дату рождения в нужный строковый формат*/
    v_birthday := to_char(l_rcus.dcusbirthday, 'yyyy-mm-dd');
    v_uuid := gis_random_uuid();
    
    /*сначала делаем запрос по паспорту РФ, если он добавлен*/
    IF t_saved_docs_aat.EXISTS('21') THEN
      v_person := inn_msg_type(v_uuid,
                              l_rcus.ccuslast_name,
                              l_rcus.ccusfirst_name,
                              l_rcus.ccusmiddle_name,
                              v_birthday,
                              '21',
                              t_saved_docs_aat('21').cpassportseries,
                              t_saved_docs_aat('21').cpassportnumber,
                              USER);
      gis_inn.p_send_req(v_person, v_status_send, v_err_msg_send);
     
      IF v_status_send = '0' THEN /*запрос был успешно поставлен в очередь*/
        gis_inn.p_get_response(v_uuid, v_status_resp, v_err_msg_resp); /*извлекаем ответ*/
          IF v_status_resp = 'Success' THEN 
            :o1 := 'Автоматически получено ИНН '||v_err_msg_resp||' и добавлено клиенту.';
            l_rcus.cCUSnumnal := v_err_msg_resp;
            account2.set_cus_record(l_rcus); /*нужно для работы остальных ФПЗ*/
            Cus_FX_Pkg.rCus.cCUSnumnal := v_err_msg_resp;
  
          ELSE
            :o1 := 'Ошибка автоматического получения ИНН '||v_err_msg_resp||'.'||chr(10)||'Обратитесь по телефону 007.';
          END IF;
      ELSE
        :o1 := 'Ошибка отправки запроса на получение ИНН '||v_err_msg_send||'.'||chr(10)||'Обратитесь по телефону 007.';
      END IF;
      
    ELSE
      i := t_saved_docs_aat.first;
      LOOP
        EXIT WHEN i IS NULL;
        
        v_person := inn_msg_type(v_uuid,
                                l_rcus.ccuslast_name,
                                l_rcus.ccusfirst_name,
                                l_rcus.ccusmiddle_name,
                                v_birthday,
                                i,
                                t_saved_docs_aat(i).cpassportseries,
                                t_saved_docs_aat(i).cpassportnumber,
                                USER);
                                
        gis_inn.p_send_req(v_person, v_status_send, v_err_msg_send);
        IF v_status_send = '0' THEN /*запрос был успешно поставлен в очередь*/
          gis_inn.p_get_response(v_uuid, v_status_resp, v_err_msg_resp); /*извлекаем ответ*/
            IF v_status_resp = 'Success' THEN 
              :o1 := 'Автоматически получено ИНН '||v_err_msg_resp||' и добавлено клиенту. ФПЗ №367.';
              l_rcus.cCUSnumnal := v_err_msg_resp;
              account2.set_cus_record(l_rcus); /*нужно для работы остальных ФПЗ*/
              Cus_FX_Pkg.rCus.cCUSnumnal := v_err_msg_resp;
              i := null;
            ELSE
              IF t_saved_docs_aat.last = i THEN
                 :o1 := 'По введенным документам не удалось автоматически получить ИНН.'||chr(10)||v_err_msg_resp||chr(10)||'По вопросам обращайтесь по телефону 007. ФПЗ №367.';
              END IF;
              i := t_saved_docs_aat.NEXT(i);
            END IF;
        ELSE
          :o1 := 'Ошибка отправки запроса на получение ИНН.'||chr(10)||v_err_msg_send||'.'||chr(10)||'Обратитесь по телефону 007. ФПЗ №367.';
        END IF;
        
      END LOOP;
    END IF;
  ELSIF v_cnt = 0 AND l_rcus.CCUSFLAG in ('1', '4') THEN
    :o1 := 'Невозможно получить ИНН автоматически, т.к. не указаны документы, удостоверяющие личность.'||chr(10)||'По вопросам обращайтесь по телефону 007. ФПЗ №367.';
  END IF;
  
end;