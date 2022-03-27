Aquameta v0.3
=============

Not your grandma's web stack.

The idea:

- Decentralized P2P network for data exchange
- Built ontop of PostgreSQL, everything lives in the database
- Build countless apps and data projects
- No command-line, fully web-based IDE
- Within an app, switch to developer/debugger mode and inspect and make changes to the app
- Built-in peer-to-peer facilities for exchanging data/apps/whatever directly with other installations
- Advanced version control over all the datas of the stack

Reality:

Still feature-incomplete and under development but maybe fun to check out!


START!
------

First install [Golang](https://golang.org/), then run:

```bash
git clone https://github.com/aquametalabs/aquameta.git
cd aquameta
go build
./aquameta --help
./aquameta -c conf/some_config_file.toml
```

<!--
{ [Download](http://aquameta.com/download) | [Demo](http://aquameta.com/demo) | [Documentation](http://aquameta.org/docs) }
-----------------------------------------------
-->

Status
------

Aquameta is an experimental project, still in early stages of development.  It is not suitable for production development and should not be used in an untrusted or mission-critical environment.

Architecture
------------

Aquameta is composed of several PostgreSQL extensions, using a `CREATE EXTENSION meta` for example.  Together, they make up a functional programming envirionment built with mostly just the database.  A thin [Golang](http://golang.org/) binary handles the connection to the database and runs a webserver.

Aquameta's PostgreSQL EXTENSIONs are:

- [meta](extensions/meta) - Writable system catalog for PostgreSQL, making most database admin tasks possible by changing live data.  Makes the database self-aware.
- [bundle](extensions/bundle) - Version control system similar to `git` but for database rows instead of files.
- [event](extensions/event) - Lets you monitor tables, rows and columns for inserts, updates and deletes, and get a PostgreSQL NOTIFY as such.
- [endpoint](extensions/endpoint) - Minimalist web framekwork implemented as PostgreSQL procedures:  A REST API, static recources, function maps and URL templates.
- [widget](extensions/widget) - Minimalist HTML component framework for building widget-based interfaces with jQuery
- [semantics](extensions/semantics) - Schema decorators, for describing columns, tables etc.

User Interface
--------------

There's an IDE, and a few demos and such on [youtube](https://www.youtube.com/channel/UCq0MVZeXqJhcpdDpQQtOs8w).

