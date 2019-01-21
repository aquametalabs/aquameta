from endpoint.db import cursor_for_request, map_errors_to_http
from json import loads
from werkzeug.exceptions import HTTPException, NotFound
from werkzeug.wrappers import Request, Response
from werkzeug.wsgi import responder


def build_directory_index(path, rows):
    return '''
            <!doctype html><html><body>
                <h1>Index of %s</h1>
                <table>
                    <tr><td><a href="%s">..</a></td><td>-</td><td>-</td></tr>
                    %s
                </table>
            </body></html>''' % (
                path,
                '/' + '/'.join(path.split('/')[:-1]), # TODO: Something smarter for parent directory link?
                ''.join(
                        '<tr>' +
                            '<td><a href="' + path + '/' + row.name + '">' + row.name + '</a></td>' +
                            '<td>' + str(row.last_mod) + '</td>' +
                            '<td>' + str(row.size) + '</td>' +
                        '</tr>' 
                        if row.show
                        else ''
                        for row in rows
                    )
            )


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
                and active = true
            ''', (request.path,))
            row = cursor.fetchone()

            # Binary resource
            if row is None:
                cursor.execute('''
                    select r.content, m.mimetype
                    from endpoint.resource_binary r
                        join endpoint.mimetype m on r.mimetype_id = m.id
                    where path = %s
                    and active = true
                ''', (request.path,))
                row = cursor.fetchone()

### Commenting out until security can be audited...
###            # File resource
###            if row is None:
###                cursor.execute('''
###                    select f.content, m.mimetype
###                    from filesystem.file f
###                        left join endpoint.mimetype_extension e on e.extension = regexp_replace(f.name, '^.*\.', '')
###                        left join endpoint.mimetype m on m.id = e.mimetype_id
###                    where f.path = (select file_id from endpoint.resource_file where path=%s and active=true)
###                ''', (request.path,))
###                row = cursor.fetchone()
###
###
###            # Directory resource
###            # Question: only directories where indexes = true?
###            if row is None:
###                cursor.execute('''
###                    with dir as (
###                        select directory_id as dir_id
###                        from endpoint.resource_directory
###                        where path=%s and indexes=true
###                    )
###                    select path, name, last_mod, size, endpoint.is_indexed(path) as show from filesystem.directory where parent_id=(select dir_id from dir)
###                    union
###                    select path, name, last_mod, size, endpoint.is_indexed(path) as show from filesystem.file where directory_id=(select dir_id from dir)
###                ''', (request.path,))
###                rows = cursor.fetchall()
###
###                if len(rows):
###                    return Response(build_directory_index(request.path, rows), content_type='text/html')
###
###            # File-in-Directory resource
###            if row is None:
###                cursor.execute('''
###                    with dir as (
###                        select directory_id as dir_id, path, char_length(path) as path_length
###                        from endpoint.resource_directory
###                        where %s like path || '%%'
###                    )
###                    select f.content, m.mimetype
###                        from filesystem.file f
###                        left join endpoint.mimetype_extension e on e.extension = regexp_replace(f.name, '^.*\.', '')
###                        left join endpoint.mimetype m on m.id = e.mimetype_id
###                        where path = (select dir_id from dir) || substring(%s from (select path_length + 1 from dir))
###                ''', (request.path,request.path))
###                row = cursor.fetchone()

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
