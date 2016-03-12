INSTALL
=======

How to build Aquameta from source.

1. Install PostgreSQL 9.5
-------------------------

Install PostgresSQL 9.5, and the postgresql-contrib package.  On Mac, try out
Postgres.app.  (see http://www.postgresql.org/download/)


2. Create a Superuser
---------------------

Under Linux, you may need to create a PostgreSQL superuser.  Postgres.app for
Mac does this for you, but for other PostgreSQL distributions:

```
eric@34f81a644855:~$ sudo -iu postgres
postgres@34f81a644855:~$ psql
psql (9.5.1)
Type "help" for help.

postgres=# create role eric superuser login;
CREATE ROLE
postgres=# \q
postgres@34f81a644855:~$
```


3. Install Aquameta into PostgreSQL
-----------------------------------

Run `./build.sh` as the user who has superuser access


4. Build and install the webserver
----------------------------------

See [core/004-aquameta_endpoint/servers/background_worker/README.md](core/004-aquameta_endpoint/servers/background_worker/README.md).


5. Browse to `localhost`
------------------------

[http://localhost:8080/](http://localhost:8080/)
