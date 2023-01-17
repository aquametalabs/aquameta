Aquameta
========

A web stack built almost entirely in PostgreSQL.  

Aquameta is a web stack composed of seven PostgreSQL extensions that loosely
correspond to the layers of a typical web stack. Under the hood, structure of a
typical web framework is represented in Aquameta as big database schema with 6
postgreSQL schemas containing ~60 tables, ~50 views and ~90 stored procedures.

Apps developed in Aquameta are represented entirely as relational data, and all
development, at an atomic level, is some form of data manipulation." Together,
they make up a functional programming envirionment built with mostly just the
database.  A thin [Golang](http://golang.org/) binary handles the connection to
the database and runs a web server.

Core extensions:

- [meta](extensions/meta) - Writable system catalog for PostgreSQL, making most
  database admin tasks possible by changing live data.  Makes the database
  self-aware.
- [bundle](extensions/bundle) - Version control system similar to `git` but for
  database rows instead of files.
- [event](extensions/event) - Lets you monitor tables, rows and columns for
  inserts, updates and deletes, and get a PostgreSQL NOTIFY as such.
- [filesystem](extensions/filesystem) - Makes the file system accessible from
  SQL
- [endpoint](extensions/endpoint) - Minimalist web framekwork implemented as
  PostgreSQL procedures:  A REST API, static recources, function maps and URL
  templates.
- [widget](extensions/widget) - Minimalist web component framework for
  building modular user interface components.
- [semantics](extensions/semantics) - Schema decorators, for describing
  columns, tables etc.

On top of these, there's a web-based IDE for developing apps.  Check out the
demos and such on
[youtube](https://www.youtube.com/channel/UCq0MVZeXqJhcpdDpQQtOs8w).

Install From Source
-------------------

First install [Golang](https://golang.org/), then run:

```bash
git clone --recurse-submodules https://github.com/aquametalabs/aquameta.git
cd aquameta
go build
./aquameta --help
./aquameta -c conf/some_config_file.toml
```

Status
------

Aquameta is an experimental project, still in early stages of development.  It
is not suitable for production development and should not be used in an
untrusted or mission-critical environment.
