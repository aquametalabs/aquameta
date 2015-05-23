# Aquameta

Aquameta Labs, Portland Oregon

Copyright (c) 2015.  All rights reserved.

A web application development platform built entirely in PostgreSQL.

http://aquameta.com/

## Prototype!

Please note - this code is an early prototype stages.  Meta and bundle layers are approaching completion, but the remaining layers are from early on in the project, and need a complete refactor.

## Project Summary

http://blog.aquameta.com/2015/04/16/introducing-aquameta/

## Build
### 1. Install PostgreSQL 9.4
Install PostgresSQL 9.4, and the postgresql-contrib package.  On Mac, try out Postgres.app.  (see http://www.postgresql.org/download/)

### 2. Create a Superuser
Under Linux, you may need to create a PostgreSQL superuser.  Postgres.app for Mac does this for you, but for other PostgreSQL distributions:
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

### 3. Install Aquameta into PostgreSQL
Run `./build.sh` as the user who has superuser access

### 4. Build and install the webserver
See core/004-aquameta_endpoint/servers/background_worker/README.

### 5. Browse to Aquameta on Localhost
http://localhost:8080/
