aquameta
========

Aquameta is a web-based development environment for building and deploying web
applications.  It is designed on the first principle of *datafication*.
Instead of storing files in the filesystem, with Aquameta, *everyting* lives in
the database, PostgreSQL.  There is no command-line interfaces or text-files,
they are replaced by a GUI, and code stored in the database.

Status
------

Aquameta is in early prototype stages, pre-0.1 release.

Features
--------

- File System - A bi-directional file system integration system
- Events - Pub/sub data change events API
- Web server - Hosts arbitrary resources and a REST/JSON API for database operations
- Bundles - A version control system similar to git but for database rows intead of files
- Widgets - Modular web components that can be reused
- Schema editor - GUI for building database tables
- Query editor - Write complex queries and views from the browser
- 100% Data - Everything is stored in the database
- Web-based IDE - Build complex applications without ever leaving the browser


Installation
------------

We recommend installing via Docker.  See the [Dockerfile](https://github.com/aquametalabs/aquameta/blob/master/Dockerfile) for instructions.

You can also build from source.  See the [INSTALL](https://github.com/aquametalabs/aquameta/blob/master/INSTALL.md) file.


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
