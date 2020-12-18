from endpoint.db import cursor_for_request
from werkzeug.wrappers import Request
from werkzeug.utils import redirect


class AuthMiddleware(object):
    def __init__(self, app):
        self.app = app
        self.login_path = '/login'
        self.session_cookie = 'SESSION'

    def do_auth(self, request, environ, start_response):
        with cursor_for_request(request) as cursor:

            # Incomplete login attempt if email/password not POSTed
            if request.form.get('email') is None or request.form.get('password') is None:
                return []

            try:
                # Attempt login
                cursor.execute(
                    'select endpoint.login(%s, %s) as session_id',
                    (request.form.get('email'), request.form.get('password'))
                )
                row = cursor.fetchone()

            except:
                # Exception raised from invalid email
                start_response('401 Unauthorized', [])
                redirect_response = redirect(request.full_path)
                return redirect_response(environ, start_response)


            if row and row.session_id:
                # Logged in

                # Redirect to redirectURL or /
                redirect_response = redirect(request.args.get('redirectURL', '/'))
                redirect_response.set_cookie(self.session_cookie, row.session_id)
                #start_response('200 Found', [('Set-Cookie', '%s=%s' % (self.session_cookie, row.session_id))])
                return redirect_response(environ, start_response)

            else:
                # Login failed from invalid password attempt
                start_response('401 Unauthorized', [])
                redirect_response = redirect(request.full_path)
                return redirect_response(environ, start_response)


    def verify_session(self, request, environ, start_response):
        environ['DB_USER'] = 'anonymous'

        if self.session_cookie in request.cookies: 
            session_id = request.cookies[self.session_cookie]

            with cursor_for_request(request) as cursor:
                try:
                    cursor.execute("select (role_id).name as role_name from endpoint.session(%s::uuid)", (session_id,))
                    row = cursor.fetchone()
                except:
                    pass
                else:
                    if row:
                        environ['DB_USER'] = row.role_name

        return self.app(environ, start_response)

    def handle_req(self, request, environ, start_response):

        # If login page requested
        if request.path == self.login_path:

            # POST handler for login attempt
            if request.method == 'POST':
                return self.do_auth(request, environ, start_response)

            # GET login page
            else:
                return self.app(environ, start_response)

        # Verify current database role and continue
        else:
            return self.verify_session(request, environ, start_response)


    def __call__(self, environ, start_response):
        return self.handle_req(Request(environ), environ, start_response)
