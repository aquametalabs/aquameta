from endpoint.db import cursor_for_request, map_errors_to_http
from werkzeug.exceptions import HTTPException
from werkzeug.wrappers import Request, Response
from werkzeug.wsgi import responder
from os import environ

import json

# For logging
import logging, sys
logger = logging.getLogger('events')
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))

@responder
def application(env, start_response):
    request = Request(env)

    try:
        with map_errors_to_http(), cursor_for_request(request) as cursor:
            logging.info('this version of the data url scheme has been deprecated. use /endpoint/new instead')
                # will be
                # select status, message, response as json
            cursor.execute('''
                select status, message, data2 as json
                from endpoint.request(%s, %s, %s::json, %s::json)
            ''', (
                request.method, # verb - GET | POST | PATCH | PUT | DELETE ...
                request.path, # path - the full path including leading slash but without query string
                json.dumps(request.args.to_dict(flat=True)), # args - "url parameters", aka parsed out query string, converted to a json string
                request.data.decode('utf8') if request.data else 'null'
            ))

            row = cursor.fetchone()
            # return Response('Hello World!')

            # TODO?
            # How come status and message are not used here?
            return Response(
                row.json,
                content_type="application/json"
            )

    except HTTPException as e:
        e_resp = e.get_response()

        if(request.mimetype == 'application/json'):
            response = Response(
                response=json.dumps({
                    "title": "Bad Request",
                    "status_code": e_resp.status_code,
                    "message": e.description
                }),
                status=e_resp.status_code,
                mimetype="application/json"
            )

            return response

        else:
            return e
