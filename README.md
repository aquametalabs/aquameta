# Aquameta

Aquameta Labs, Portland Oregon

Copyright (c) 2015.  All rights reserved.

A web application development platform built entirely in PostgreSQL.

http://aquameta.com/

## Prototype!

Please note - this code is an early prototype stages.  Meta and bundle layers are approaching completion, but the remaining layers are from early on in the project, and need a complete refactor.

## Project Summary

http://blog.aquameta.com/introducing-aquameta

## Build
1. Install PostgresSQL 9.4, and the postgresql-contrib package.  On Mac, try out Postgres.app.  (see http://www.postgresql.org/download/)
2. If you're under Linux, create a superuser in PostgreSQL if necessary.  Postgres.app for mac does this for you, but for other PostgreSQL distributions:
```
eric@34f81a644855:~$ sudo -iu postgres
postgres@34f81a644855:~$ psql
psql (9.4.1)
Type "help" for help.

postgres=# create role eric superuser login;
CREATE ROLE
postgres=# \q
postgres@34f81a644855:~$
```
3. Run `./build.sh` as the user who has superuser access
4. Build and install the webserver.  See core/004-www/servers/background_worker/README.
5. http://localhost:8080/
