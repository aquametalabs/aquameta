from contextlib import contextmanager
from os import environ
from psycopg2 import connect as pg_connect, DataError, IntegrityError, OperationalError, ProgrammingError, InternalError
from psycopg2.extras import register_composite, NamedTupleCursor
from werkzeug.exceptions import BadRequest, Forbidden, NotFound, Unauthorized


def connect(request):
    conn_info = {
        'host':     environ['DB_HOST'],
        'user':     request.environ.get('DB_USER', 'anonymous'),
        'database': environ['DB_NAME'],
    }

    return pg_connect(cursor_factory=NamedTupleCursor, **conn_info)


@contextmanager
def cursor_for_request(request):
    try:
        with connect(request) as db_conn:
            cursor = db_conn.cursor()
            yield cursor

    finally:
        db_conn.close()


@contextmanager
def map_errors_to_http():
    try:
        yield

    except (DataError, IntegrityError, InternalError, OperationalError, ProgrammingError) as err:
        err_str = str(err)

        if err_str.endswith('does not exist'): # FIXME: find a way for psycopg2 to emit better errors...
            raise NotFound(err_str)
        elif 'is not permitted to log in' in err_str:
            raise Unauthorized(description="Your account is currently disabled.")
        elif 'permission denied for' in err_str:
            raise Forbidden(description="Your user has not been granted access to the requested resource.")
        else:
            raise BadRequest(err_str)
