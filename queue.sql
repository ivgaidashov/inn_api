/*create a message type*/
CREATE OR REPLACE TYPE inn_msg_type AS OBJECT (
  crequestid            VARCHAR2(36),
  clastname             VARCHAR2(60),
  cfirstname            VARCHAR2(60),
  csecond_name          VARCHAR2(60),
  cbirthday             VARCHAR2(10),
  cdocumentcode         VARCHAR2(5),
  cpassportseries       VARCHAR2(30),
  cpassportnumber       VARCHAR2(30),
  cuser                 varchar2(50)
);

/*create a table*/
begin
   DBMS_AQADM.create_queue_table (
   queue_table            =>  'gis_inn_queue_tab', 
   queue_payload_type     =>  'inn_msg_type');
end;

/*create a queue*/
begin
  DBMS_AQADM.create_queue (
   queue_name            =>  'gis_inn_queue',
   queue_table           =>  'gis_inn_queue_tab');
end;

/*start the queue*/
begin
DBMS_AQADM.start_queue (
   queue_name         => 'gis_inn_queue', 
   enqueue            => TRUE);
end;

/*send a message*/
DECLARE
  l_enqueue_options     DBMS_AQ.enqueue_options_t;
  l_message_properties  DBMS_AQ.message_properties_t;
  l_message_handle      RAW(16);
  l_event_msg           inn_msg_type;
BEGIN
  l_event_msg := inn_msg_type(gis_random_uuid(), 'Каринпина','Ирина','Викторовна','1970-01-01','21', '22 05', '5655452', USER);

  DBMS_AQ.enqueue(queue_name          => 'gis_inn_queue',        
                  enqueue_options     => l_enqueue_options,     
                  message_properties  => l_message_properties,   
                  payload             => l_event_msg,             
                  msgid               => l_message_handle);

  COMMIT;
END;

/*retrieve a message*/
DECLARE
  l_dequeue_options     DBMS_AQ.dequeue_options_t;
  l_message_properties  DBMS_AQ.message_properties_t;
  l_message_handle      RAW(16);
  l_event_msg           inn_msg_type;
BEGIN
  DBMS_AQ.dequeue(queue_name          => 'gis_inn_queue',
                  dequeue_options     => l_dequeue_options,
                  message_properties  => l_message_properties,
                  payload             => l_event_msg,
                  msgid               => l_message_handle);

  DBMS_OUTPUT.put_line ('crequestid          : ' || l_event_msg.crequestid);
  DBMS_OUTPUT.put_line ('clastname                :' || l_event_msg.clastname);
  DBMS_OUTPUT.put_line ('csecond_name        : ' || l_event_msg.csecond_name);
  DBMS_OUTPUT.put_line ('cbirthday               : ' || l_event_msg.cbirthday);
  DBMS_OUTPUT.put_line ('cdocumentcode               : ' || l_event_msg.cdocumentcode);
  DBMS_OUTPUT.put_line ('cpassportseries               : ' || l_event_msg.cpassportseries);
  DBMS_OUTPUT.put_line ('cpassportnumber               : ' || l_event_msg.cpassportnumber);
  DBMS_OUTPUT.put_line ('cuser               : ' || l_event_msg.cuser);
  COMMIT;
END;