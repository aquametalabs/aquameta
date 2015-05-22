Building
--------

1. Install qpfiffer's fork of [libwebsockets](https://github.com/qpfiffer/libwebsockets)
1. If you're not running PostgreSQL on port 5432 or doing something else non-default, you may need to configure the settings by which pg_http will connect to the database.  Edit pg_http.c match your settings:

````c
conn = PQconnectdb("dbname=aquameta");
````

as described here: http://www.postgresql.org/docs/8.1/static/libpq.html#LIBPQ-CONNECT

1. make
1. make install

Then in Postgres:

````
public=# create extension pg_http;
CREATE EXTENSION

````

and finally, make sure that the following line is in your `postgresql.conf`
somewhere:

````
...
shared_preload_libraries = 'pg_http'
...
````
