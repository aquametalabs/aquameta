from endpoint.db import cursor_for_request, map_errors_to_http
from json import loads
from werkzeug.exceptions import HTTPException, NotFound
from werkzeug.wrappers import Request, Response
from werkzeug.wsgi import responder


def build_directory_index(path, rows):
    return '''
            <!doctype html><html><body>
                <h1>Index of %s</h1>
                <ul>%s</ul>
            </body></html>''' % (path, ''.join('<li><a href="'+row.path+'">'+row.path.split('/')[-1]+'</a></li>' for row in rows))

@responder
def application(env, start_response):
    request = Request(env)

    try:
        with map_errors_to_http(), cursor_for_request(request) as cursor:

            # Text resource
            cursor.execute('''
                select r.content, m.mimetype
                from endpoint.resource r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where path = %s
            ''', (request.path,))
            row = cursor.fetchone()

            # Binary resource
            if row is None:
                cursor.execute('''
                    select r.content, m.mimetype
                    from endpoint.resource_binary r
                        join endpoint.mimetype m on r.mimetype_id = m.id
                    where path = %s
                ''', (request.path,))
                row = cursor.fetchone()

            # File resource
            if row is None:
                cursor.execute('''
                    select f.content, m.mimetype
                    from endpoint.resource_file r
                        left join endpoint.mimetype_extension e on e.extension = regexp_replace(r.file_id, '^.*\.', '')
                        left join endpoint.mimetype m on m.id = e.mimetype_id
                        join filesystem.file f on f.path = r.file_id
                    where r.file_id = %s
                ''', (request.path,))
                row = cursor.fetchone()

            # Directory resource
            # Question: only directories where indexes = true?
            if row is None:
                cursor.execute('''
                    select c.path
                    from endpoint.resource_directory r
                        join (
                            select path, parent_id from filesystem.directory
                            union
                            select path, directory_id as parent_id from filesystem.file
                        ) c on c.parent_id = r.directory_id
                    where r.directory_id = %s and r.indexes = true
                ''', (request.path,))
                rows = cursor.fetchall()

                if len(rows):
                    return Response(build_directory_index(request.path, rows), content_type='text/html')

            # Should this redirect to /login?
            # That would mean: Resource Not Found = Resource Not Authorized
            # Which is accurate considering RLS hides unauthorized data
            # No because auth should occur in widgets, no redirecting
            if row is None:
                # Is this returning a 404?
                raise NotFound

            return Response(row.content, content_type='text/plain' if row.mimetype is None else row.mimetype)

    except HTTPException as e:
        return e
