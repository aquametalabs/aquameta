Building
--------

1. Install qpfiffer's fork of [libwebsockets](https://github.com/qpfiffer/libwebsockets)
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
