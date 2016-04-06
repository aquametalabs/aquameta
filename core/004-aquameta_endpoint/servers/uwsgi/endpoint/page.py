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

            # If endpoint.resource was a view that contained text and binary resources, these 2 queries could be combined
            cursor.execute('''
                select r.content, m.mimetype
                from endpoint.resource r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where path = %s
            ''', (request.path,))
            row = cursor.fetchone()

            if row is None:
                cursor.execute('''
                    select r.content, m.mimetype
                    from endpoint.resource_binary r
                        join endpoint.mimetype m on r.mimetype_id = m.id
                    where path = %s
                ''', (request.path,))
                row = cursor.fetchone()

            if row is None:
                cursor.execute('''
                    select f.content, m.mimetype
                    from (select file_id, regexp_replace(file_id, '^.*\.', '') as extension from endpoint.resource_file) as r
                        join endpoint.mimetype_extension e on e.extension = r.extension
                        join endpoint.mimetype m on m.id = e.mimetype_id
                        join filesystem.file f on f.path = r.file_id
                    where r.file_id = %s
                ''', (request.path,))
                row = cursor.fetchone()

            # Should this redirect to /login?
            # That would mean: Resource Not Found = Resource Not Authorized
            # Which is accurate considering RLS hides unauthorized data
            # No because auth should occur in widgets, no redirecting
            if row is None:
                raise NotFound

            return Response(row.content, content_type=row.mimetype)

    except HTTPException as e:
        return e
