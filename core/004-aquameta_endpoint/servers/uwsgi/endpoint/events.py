from endpoint.db import cursor_for_request
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from psycopg2 import InternalError, Warning
from werkzeug.contrib.wrappers import JSONRequestMixin
from werkzeug.wrappers import Request
from os import urandom

import json, logging, uwsgi, sys
from uuid import UUID




#def get_session_id(request, cursor):
#    session_id = None
#    if 'token' in request.args:
#        cursor.execute('''
#            select id
#            from session.session
#            where id = %s
#        ''', (request.args['token'],))
#
#        session_row = cursor.fetchone()
#        if session_row:
#            session_id = session_row.id
#
#    # Create new session
#    #if session_id is None:
#        #session_id = new_session(cursor)
#
#    return session_id


    
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

            #session_id = get_session_id(request, cursor)

            logging.info('connection established')
            #logging.info('event/table/session/row/%s:connected (role: %s)' % (session_id, env['DB_USER']))

            db_conn_fd = db_connection.fileno()
            websocket_fd = uwsgi.connection_fd()

            #cursor.execute('listen "event/table/session/rows/%i"' % session_id)

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
                            if cmd['method'] != 'ping':
                                logging.info('cmd_json %s' % (cmd_json))

                            if cmd:
                                try:
                                    if cmd['method'] == 'attach':
                                        #session_id = get_session_id(request, cursor)
                                        session_id = cmd['session_id']

                                        if session_id is not None:
                                            logging.info('session %s:connected (role: %s)' % (session_id, env['DB_USER']))
#                                            cursor.execute('listen %i' % session_id)

                                            # This will execute listen, and notify of all existing events
                                            cursor.execute('''
                                                select session.session_attach(%s);
                                            ''', (session_id,))

#                                            cursor.execute('''
#                                                select event from event.event where session_id = %s;
#                                            ''', (session_id,))
#
#                                            for row in cursor:
#                                                uwsgi.websocket_send(json.dumps(row))
#                                                logging.info('session %s:sent_json (role: %s)' % (session_id, env['DB_USER']))

                                    elif cmd['method'] == 'detach':
                                        logging.info('session %s:disconnected (role: %s)' % (session_id, env['DB_USER']))
#                                        cursor.execute('unlisten %i' % session_id)

                                        session_id = cmd['session_id']
                                        cursor.execute('''
                                            select session_detach(%s);
                                        ''', (session_id,))

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
                            #del db_connection.notifies[:]
                            logging.info('---------------------------- db notifies')

                            # Blast off notify's
                            for notify in db_connection.notifies:
                                logging.info('---------------------------- notifies %s' % (notify))
                                uwsgi.websocket_send(json.dumps(notify.payload))
                                logging.info('session %s:sent_json (role: %s)' % (session_id, env['DB_USER']))

                    else:
                        # handle timeout of above wait_fd_read for ping/pong
                        uwsgi.websocket_recv_nb()

            except OSError as err:
                logging.info('session %s:disconnected (role: %s)' % (session_id, env['DB_USER']))

        return []
