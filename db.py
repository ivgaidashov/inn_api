from datetime import datetime
import cx_Oracle
import base64
import requests
import time
import json
import uuid
from utils import log_error, log_info, log_warn, log_new_line, send_email
from conf import master_token, oracle_database, oracle_ip, oracle_username, oracle_password, server_url, ep_at, ep_singleinn, headers

class Database(object):
   connection = None
   def __init__(self):
       while Database.connection is None:
           try:
               log_info('Подключение к БД')
               dsn_tns = cx_Oracle.makedsn(oracle_ip, '1521', service_name=oracle_database)
               Database.connection = cx_Oracle.connect(user=oracle_username, password=oracle_password, dsn=dsn_tns)
               if Database.connection is None:
                   time.sleep(5)
           except cx_Oracle.Error as error:
               log_error('Ошибка подключения к БД: ' + str(error))
           finally:
               log_new_line()
   
   def save_access_point(ap, datestart, dateend):
        log_info('Сохранение нового accessPoint в БД')
        statement = "insert into gis_inn_access_tokens (caccesstoken, dstartdate, denddate) values (:1, :2, :3)"
        try:
            with Database.connection.cursor() as cursor:
                cursor.execute(statement, [ap, datestart, dateend])
                Database.connection.commit()
                log_info(f'Сохранён {ap}')
        except cx_Oracle.Error as error:
            log_error('Не удалось сохранить в БД глобальный идентификатор загрузки: ' + str(error))
        finally:
            log_new_line()

   def get_access_point():
       log_info('Получение accessPoint из БД')
       statement = "SELECT CACCESSTOKEN, DENDDATE FROM gis_inn_access_tokens ORDER BY DENDDATE DESC FETCH FIRST 1 ROWS ONLY"
       try:
            with Database.connection.cursor() as cursor:
                cursor.execute(statement)
                row = cursor.fetchone()
                if row:
                    return row[0], row[1]
                else:
                    return None, None

       except cx_Oracle.Error as error:
           log_error('Не удалось получить accessPoint из БД: ' + str(error))
       finally:
            log_new_line()

   def insert_response(data, status, value, date):
        log_info('Сохранение результата в таблице gis_inn_responses')
        statement = f"insert into gis_inn_responses values (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12)"
        try:
            with Database.connection.cursor() as cursor:
                cursor.execute(statement, [data["id"], status, value, data["lastName"], data["firstName"], data["second_name"], data["birthday"], data["documentCode"], data["passportSeries"], data["passportNumber"], data["user"], date ])
                Database.connection.commit()
                log_info(f'Результат сохранен')
        except cx_Oracle.Error as error:
            log_error('Не удалось сохранить в БД ответ на запрос: ' + str(error))

   def close(self):
       log_info('Закрытие соединения с БД')
       Database.connection.close()

class INN_Api(object):
    access_token = None
    expiration_date = None
    def __init__(self):
        log_info('Инициализация класса INN_Api')
        at_raw, INN_Api.expiration_date = Database.get_access_point()
        if at_raw:
            expired = self.has_expired()
            if expired is False:
                INN_Api.access_token = self.convert_to_base64(at_raw)
            else:
                self.get_new_access_token() 
        else:
            self.get_new_access_token()

    def get_header(self, category):
        new_header = headers
        new_header['X-Request-Id'] = str(uuid.uuid1())
        print('X-Request-Id', new_header['X-Request-Id'])

        if category ==  1: #без токена
            return new_header
        elif category == 2: #с токеном
            new_header['Authorization'] = f'Bearer {self.access_token}'
            return new_header
        else:
            return new_header

    def send_request(self, type, endpoint, hdrs_auth, data):
        try:
            response = requests.request(type, endpoint, headers=self.get_header(hdrs_auth), data=data)
            log_info(response)
            resp_json = json.loads(response.text)
            log_info(resp_json)
            return resp_json
        except Exception as e:
            log_error(e)


    def convert_to_base64(self, token):
        log_info(f'Конвертация accessToken {token} в base64')
        message_bytes = token.encode('ascii')
        base64_bytes = base64.b64encode(message_bytes)
        base64_message = base64_bytes.decode('ascii')

        log_info(f'Результат конвертации: {base64_message}')
        return base64_message
    
    def get_new_access_token(self):
        log_info('Получение нового токена')
        url = server_url + ep_at
        payload = json.dumps({"masterToken": master_token})

        response = self.send_request('POST', url, 1, payload)

        accessToken=self.convert_to_base64(response['accessToken'])
        accessTokenStartDate=datetime.strptime(response['accessTokenStartDate'], "%Y-%m-%dT%H:%M:%S.%f%z")
        accessTokenEndDate=datetime.strptime(response['accessTokenEndDate'], "%Y-%m-%dT%H:%M:%S.%f%z")
        
        INN_Api.access_token = accessToken
        INN_Api.expiration_date = accessTokenEndDate
        Database.save_access_point(response['accessToken'], accessTokenStartDate, accessTokenEndDate)

    def has_expired(self):
        now = datetime.now().timestamp()
        if now >= INN_Api.expiration_date.timestamp():
            log_info(f'Истёр срок действия {INN_Api.expiration_date} текущего токена')
            return True
        else:
            return False
    
    def get_single_inn(self, person):
        result = None
        log_info(f'Запрос на получение одного ИНН для {person}')

        expired = self.has_expired()
        if expired:
            self.get_new_access_token()

        url=server_url+ep_singleinn
        payload = json.dumps(person)
        
        response = self.send_request('POST', url, 2, payload) #requests.request("POST", url, headers=headers, data=payload)
        
        if 'error' in response:
            if response['error'] == 'openApi.tokenAccessDenied':
                log_warn(f'Сервер не принял accessToken. {response["message"]}. ')
                log_new_line()
                self.get_new_access_token()
                response = self.send_request('POST', url, 2, payload) #requests.request("POST", url, headers=headers, data=payload)
            else:
                log_error(f'Получена необрабатываемая ошибка {response["message"]}')
                Database.insert_response(person["id"], 'Error', response["message"], person["user"])
                send_email(['ivgaide@domain.ru'], 'API ИНН - ошибка', f'Получена необрабатываемая ошибка {response["message"]}')
        
        if 'responseDocumentItems' in response:
            result = response['responseDocumentItems'][0]
            status = None
            value = None
            if result['businessError']:
                status = 'Error'
                value = 'Код ' + result['businessError']['code'] + '. Описание: ' + result['businessError']['message'] + '. Дополнительно: ' + json.dumps(result['businessError']['additionalInfo']).encode().decode("unicode-escape")
            else:
                status = 'Success'
                value = result['inn']
            result = {'status': status, 'value': value}
            log_info(person)
            log_info(f'{person["id"]}, {status}, {value}')
            
            Database.insert_response(person, status, value, datetime.now())

            return result
        else:
            log_error('Не найден тег responseDocumentItems')

        return result

        
