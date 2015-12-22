from endpoint.db import cursor_for_request
from werkzeug.wrappers import Request


class AuthMiddleware(object):
    def __init__(self, app):
        self.app = app
        self.login_path = '/login' # TODO remove this hardcoded login path when row-level permissions lands; should just react to db causing 401
        self.session_cookie = 'SESSION'

    def do_auth(self, request, start_response):
        with cursor_for_request(request) as cursor:
            cursor.execute(
                'select endpoint.login(%s) as token',
                (request.args['hash'],)
            )

            row = cursor.fetchone()

            if row and row.token:
                start_response('200 Found', [('Set-Cookie', '%s=%s' % (self.session_cookie, row.token))])
            else:
                start_response('401 Unauthorized', [])

            return []

    def verify_session(self, request, environ, start_response):
        environ['DB_USER'] = 'guest'

        if self.session_cookie in request.cookies: 
            token = request.cookies['SESSION']

            with cursor_for_request(request) as cursor:
                cursor.execute("select username from endpoint.session where token = %s", (token,))

                row = cursor.fetchone()
                if row:
                    environ['DB_USER'] = row.username

        return self.app(environ, start_response)

    def handle_req(self, request, environ, start_response):
        if request.path == self.login_path:
            if 'hash' in request.args:
                return self.do_auth(request, start_response)
            else:
                return self.app(environ, start_response)
        else:
            return self.verify_session(request, environ, start_response)

    def __call__(self, environ, start_response):
        return self.handle_req(Request(environ), environ, start_response)
