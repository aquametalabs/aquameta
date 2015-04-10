from endpoint.db import cursor_for_request
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from psycopg2 import InternalError, Warning
from werkzeug.contrib.wrappers import JSONRequestMixin
from werkzeug.wrappers import Request
from os import urandom

import json, logging, uwsgi, sys
from uuid import UUID



def new_session(cursor):
    token = UUID(bytes=urandom(16))

    cursor.execute('''
        insert into event.session (token, owner_id)
        values (%s, (
            select r.id
            from meta.role r
            where r.name = session_user    --pg magic name, not referring to event.session
            limit 1
        ))
        returning id
    ''', (str(token),))

    uwsgi.websocket_send('''{
        "method": "set_token",
        "args": {
            "token": "%s"
        }
    }''' % (token,))

    session_id = cursor.fetchone().id

    return session_id


def get_session_id(request, cursor):
    session_id = None
    if 'token' in request.args:
        cursor.execute('''
            select id
            from event.session
            where token = %s
        ''', (request.args['token'],))

        session_row = cursor.fetchone()
        if session_row:
            session_id = session_row.id

    if session_id is None:
        session_id = new_session(cursor)

    return session_id


    
logger = logging.getLogger('events')
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))


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

            session_id = get_session_id(request, cursor)

            logging.info('event/table/session/row/%s:connected (role: %s)' % (session_id, env['DB_USER']))

            db_conn_fd = db_connection.fileno()
            websocket_fd = uwsgi.connection_fd()

            cursor.execute('listen "event/table/session/rows/%i"' % session_id)

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
                                    if cmd['method'] == 'subscribe':
                                        selector, type = cmd['args']['selector'].rsplit(':', 1)
                                        cursor.execute("select event.subscribe_session(%s, %s, %s);", (session_id, selector, type))

                                    elif cmd['method'] == 'unsubscribe':
                                        selector, type = cmd['args']['selector'].rsplit(':', 1)
                                        cursor.execute("select event.unsubscribe_session(%s, %s, %s);", (session_id, selector, type))

                                except Warning as err:
                                    logging.error(str(err))
                                    uwsgi.websocket_send(json.dumps({
                                        "method": "log",
                                        "args": {
                                            "level": "warning",
                                            "message": err.diag.message_primary
                                        }
                                    }))

                    elif fd == db_conn_fd:
                        db_connection.poll()

                        if db_connection.notifies:
                            del db_connection.notifies[:]

                            cursor.execute('''
                                select *
                                from event.session_queued_events_json(%s)
                            ''', (session_id,))

                            qe_ids = []
                            logging.info('event/table/session/row/%s:flushing_queue (role: %s)' % (session_id, env['DB_USER']))

                            for row in cursor:
                                uwsgi.websocket_send(json.dumps(row.event_json))
                                logging.info('event/table/session/row/%s:sent_json (role: %s)' % (session_id, env['DB_USER']))
                                qe_ids.append(row.queued_event_id)

                            cursor.execute('''
                                delete from event.queued_event qe
                                where qe.id = any(%s)
                            ''', (qe_ids,))
                    else:
                        # handle timeout of above wait_fd_read for ping/pong
                        uwsgi.websocket_recv_nb()

            except OSError as err:
                logging.info('event/table/session/row/%s:disconnected (role: %s)' % (session_id, env['DB_USER']))

        return []
