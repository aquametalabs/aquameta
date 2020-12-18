from endpoint.db import cursor_for_request
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from psycopg2 import Warning
from werkzeug.wrappers import Request
import json, logging, uwsgi, sys

from werkzeug.datastructures import ImmutableMultiDict

logger = logging.getLogger('events')
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))


def handle_db_notifications(conn):
    conn.poll()
    while conn.notifies:
        notify = conn.notifies.pop(0)
        uwsgi.websocket_send('''{
            "method": "event",
            "data": %s
        }''' % (json.dumps(notify.payload),))
        # logging.info('sent json notification')


def request_method(cmd, cursor):
    query_data = ImmutableMultiDict(json.loads(cmd['query']))
    post_data = json.dumps(cmd['data'])

    logging.info('websocket endpoint request: %s, %s, %s, %s, %s' % (
        '0.3',          # API version               - 0.1, 0.3, etc.
        cmd['verb'],    # HTTP method               - GET, POST, PATCH, DELETE
        cmd['uri'],     # selector                  - '/relation/widget/dependency_js'
        query_data,     # query string arguments    - including event.session id
        post_data))     # post data

    cursor.execute(
        """select status, message, response, mimetype
             from endpoint.request({version}, {verb}, {path}, {query}, {data});""".format(
                 version = cmd['version'],
                 verb = cmd['verb'],
                 path = cmd['uri'],
                 query = json.dumps(query_data).to_dict(flat=False),
                 data = post_data))

    result = cursor.fetchone()

    uwsgi.websocket_send('''{
        "method": "response",
        "request_id": "%s",
        "data": %s
    }''' % (cmd['request_id'], result.response))


def attach_method(cmd, cursor, db_connection, env):
    session_id = cmd['session_id']
    if session_id is not None:
        cursor.execute('select event.session_attach(%s);', (session_id,))
        logging.info('session attached: %s (role: %s)' % (session_id, env['DB_USER']))
        handle_db_notifications(db_connection)

        uwsgi.websocket_send('''{
            "method": "response",
            "request_id": "%s",
            "data": "true"
        }''' % (cmd['request_id'],))


def detach_method(cmd, cursor, env):
    session_id = cmd['session_id']
    if session_id is not None:
        cursor.execute('select event.session_detach(%s);', (session_id,))
        logging.info('session detached: %s (role: %s)' % (session_id, env['DB_USER']))

        uwsgi.websocket_send('''{
            "method": "response",
            "request_id": "%s",
            "data": "true"
        }''' % (cmd['request_id'],))


def application(env, start_response):
    request = Request(env)

    try:
        uwsgi.websocket_handshake(env['HTTP_SEC_WEBSOCKET_KEY'],
                                  env.get('HTTP_ORIGIN', ''))
    except OSError as err:
        logging.info('handshake_failed')

    else:
        with cursor_for_request(request) as cursor:
            db_connection = cursor.connection
            db_connection.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

            db_conn_fd = db_connection.fileno()
            websocket_fd = uwsgi.connection_fd()

            logging.info('connection established')

            try:
                while True:
                    uwsgi.wait_fd_read(websocket_fd)
                    uwsgi.wait_fd_read(db_conn_fd)
                    uwsgi.suspend()

                    fd = uwsgi.ready_fd()

                    if fd == websocket_fd:
                        cmd_json = uwsgi.websocket_recv_nb()

                        if cmd_json:
                            cmd = json.loads(cmd_json.decode('utf-8'))

                            if cmd:
                                try:
                                    if cmd['method'] != 'ping':
                                        logging.info('command received: %s' % cmd['method'])

                                    if cmd['method'] == 'request':
                                        request_method(cmd, cursor)

                                    elif cmd['method'] == 'attach':
                                        attach_method(cmd, cursor, db_connection, env)

                                    elif cmd['method'] == 'detach':
                                        detach_method(cmd, cursor, db_connection, env)

                                except Warning as err:
                                    logging.error(str(err))
#                                    uwsgi.websocket_send(json.dumps({
#                                        "method": "log",
#                                        "args": {
#                                            "level": "warning",
#                                            "message": err.diag.message_primary
#                                        }
#                                    }))

                    elif fd == db_conn_fd:
                        handle_db_notifications(db_connection)

                    else:
                        logging.info('timeout reached') # This is never reached

                        # handle timeout of above wait_fd_read for ping/pong
                        uwsgi.websocket_recv_nb()

            except (OSError, IOError) as err:
                logging.info('connection closed (role: %s)' % env['DB_USER'])

        return []
