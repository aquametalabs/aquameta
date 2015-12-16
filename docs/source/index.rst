aquameta
========

Aquameta is a web-based development environment for building and deploying web
applications.  Instead of storing files in the filesystem, with Aquameta,
*everyting* lives in the database, PostgreSQL.  There is no command-line
interfaces or text-files, they are replaced by a GUI, and code stored in the
database.

Features
--------

- 100% Data - Everything is stored in the database
- Web-based IDE - Build complex applications without ever leaving the browser
- Bundles - A version control system similar to git but for database rows intead of files
- Widgets - Modular web components that can be reused
- Events - Pub/sub data change events API
- Web server - Hosts arbitrary resources and a REST/JSON API for database operations
- Schema editor - GUI for building database tables
- Query editor - Write complex queries and views from the browser
- Language-agnostic - Server-side functions can be written in any of PostgreSQL's [supported languages]().


Installation
------------

We recommend installing via Docker.

git clone 
cd aquameta
docker build -t aquametalabs/aquameta:latest .



Contribute
----------

- Issue Tracker: github.com/aquametalabs/aquameta/issues
- Source Code: github.com/aquametalabs/aquameta

Support
-------

If you are having issues, please let us know.
We have a mailing list located at: aquameta-discuss@google-groups.com

License
-------

The project is licensed under the GPL.
