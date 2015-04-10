from endpoint.db import cursor_for_request, map_errors_to_http
from json import loads
from werkzeug.exceptions import HTTPException, NotFound
from werkzeug.wrappers import Request, Response
from werkzeug.wsgi import responder


@responder
def application(env, start_response):
    request = Request(env)

    try:
        with map_errors_to_http(), cursor_for_request(request) as cursor:
            cursor.execute('select content from www.page where path = %s', (request.path,))
            row = cursor.fetchone()

            if row is None:
                raise NotFound
            else:
                return Response(row.content, content_type='text/html')

    except HTTPException as e:
        return e
