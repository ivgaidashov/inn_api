from utils import log_warn, log_error, send_email

from datetime import date
from db import Database, INN_Api
import os

conn = Database()
api = INN_Api()

if __name__ == "__main__":
    with conn.connection.cursor() as cursor:
        return_val = cursor.callfunc("pcaliso.is_workday", int, ['RUR', date.today()])
        if return_val == 0:
            #https://github.com/oracle/python-cx_Oracle/blob/main/samples/tutorial/solutions/aq-dequeue.py
            try:
                inn_type = conn.connection.gettype("INN_MSG_TYPE")
                queue = conn.connection.queue("GIS_INN_QUEUE", inn_type)
                while True:
                    msg = queue.deqone()
                    conn.connection.commit()
                    inn_result = api.get_single_inn({ "id": msg.payload.CREQUESTID ,  "lastName": msg.payload.CLASTNAME,	"firstName": msg.payload.CFIRSTNAME,
                                            "second_name": msg.payload.CSECOND_NAME,
                                            "birthday": msg.payload.CBIRTHDAY,
                                            "documentCode": msg.payload.CDOCUMENTCODE,
                                            "passportSeries": msg.payload.CPASSPORTSERIES,
                                            "passportNumber": msg.payload.CPASSPORTNUMBER,
                                            "user": msg.payload.CUSER})
                    print(inn_result)
            except KeyboardInterrupt:
                print('Terminated')
            finally:
                conn.close()  
        elif return_val == 1:
            log_warn('Выходной день. Скрипт останавливает работу')
            send_email(['ivgaide@domain.ru'], 'API ИНН - выходной день', f'В выходной день скрипт не работает')
            conn.close()  
        else:
            log_error(f'Ошибка получения типа дня {return_val}')
            send_email(['ivgaide@domain.ru'], 'API ИНН - ошибка', f'Ошибка получения типа дня {return_val}')
            conn.close()  

        