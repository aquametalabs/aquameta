Aquameta
========

A web stack built almost entirely in PostgreSQL.  

Status
------

Aquameta is an experimental project, still in early stages of development.  It
is not suitable for production development and should not be used in an
untrusted or mission-critical environment.

Overview
--------
Aquameta is a web stack composed of seven PostgreSQL extensions that loosely
correspond to the layers of a typical web stack. Under the hood, the structure
of a typical web framework is represented as a big database schema containing
~60 tables, ~50 views and ~90 stored procedures.

Apps developed in Aquameta are represented entirely as relational data, and all
development, at an atomic level, is some form of data manipulation." Together,
they make up a functional programming envirionment built with mostly just the
database.  A thin [Golang](http://golang.org/) binary handles the connection to
the database and runs a web server.

Core extensions:

- [meta](https://github.com/aquameta/meta) - Writable system catalog for
  PostgreSQL, making most database admin tasks possible by changing live data.
  Makes the database self-aware.
- [bundle](extensions/bundle) - Version control system similar to `git` but for
  database rows instead of files.
- [event](extensions/event) - Lets you monitor tables, rows and columns for
  inserts, updates and deletes, and get a PostgreSQL NOTIFY as such.
- [filesystem](extensions/filesystem) - Makes the file system accessible from
  SQL
- [endpoint](extensions/endpoint) - Minimalist web framekwork implemented as
  PostgreSQL procedures:  A REST API, static recources, function maps and URL
  templates.
- [widget](extensions/widget) - Minimalist web component framework for building
  modular user interface components.
- [semantics](extensions/semantics) - Schema decorators, for describing
  columns, tables etc.

On top of these, there's a web-based IDE for developing apps.  Check out the
demos and such on
[youtube](https://www.youtube.com/channel/UCq0MVZeXqJhcpdDpQQtOs8w).


Motivation
----------

The web stack is very complicated, and frankly a bit of a mess.  Aquameta's
philosophy is that the cause of this mess is the underlying information model
of "files plus syntax".  Under the hood, web stacks *have structure*, but that
structure is latent and heterogeneous.  The heirarchical file system isn't
adequate for handling the level of complexity in the web stack.

Putting things in the database makes them uniform and clean. There are many
architectural advantages, but to highlight a few:

- An all-data web stack means that the various layers of the stack have a
  *shared information model*.  As such, you can combine various layers of the
  stack into a single bundle with ease, because it's all just data.  Whether a
  bundle be an entire app, a Javascript dependency, a collection of user data,
  some database schema and functions, or any other way slice and dice a
  project, as long as it is all data, it makes a single coherent bundle.
- When all the layers are data, you can make tools that work with data,
  generally, and they can apply to all the layers of the stack at the same
  time.

The result is a vast increase in potential for modularity -- reusable
components.  That means we can share code and data in a much more effective
way, and build on each other's work more coherently than in the file-based
paradigm.

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
