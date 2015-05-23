Building
--------

### 1. Install libwebsockets

Install qpfiffer's fork of [libwebsockets](https://github.com/qpfiffer/libwebsockets)


### 2. Modify pg_http.c (if necessary)

If you're not running PostgreSQL on port 5432 or doing something else
non-default, you may need to configure the settings by which pg_http will
connect to the database.  Edit pg_http.c match your settings:


````c
conn = PQconnectdb("dbname=aquameta");
````

as described here: [http://www.postgresql.org/docs/8.1/static/libpq.html#LIBPQ-CONNECT](http://www.postgresql.org/docs/8.1/static/libpq.html#LIBPQ-CONNEC)T

### 3. Build

Run the following commands in the `background_worker` directory:

````
make
make install
````

### 4. Create the extension in PostgreSQL

Postgres:

````
public=# create extension pg_http;
CREATE EXTENSION
````


### 5. Enable the extension in `postgresql.conf`

Finally, modify the `shared_preload_libraries` variable of your `postgresql.conf`:

````
...
shared_preload_libraries = 'pg_http'
...
````

then restart PostgreSQL to enable the change.
