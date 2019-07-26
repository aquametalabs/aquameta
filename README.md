aquameta
========

Overview
--------
Aquameta is a web-based IDE for full-stack web development.  Developers can manage HTML, CSS, Javascript, database schema, views, templates, routes, tests and documentation, and do version control, branching, pushing, pulling, user management and permissions, all from a single web-based IDE.  In theory.  And mostly in practice.

* [introduction](http://blog.aquameta.com/introducing-aquameta/)
* [blog](http://blog.aquameta.com/)
* [demo video](https://www.youtube.com/watch?v=ZOpj8lvNJtg)
* [get started](docs/quickstart.md)
* [cheat sheet](docs/cheatsheet.md)

Status
------
Aquameta is an experimental project, still in early stages of development.  It is not suitable for production development and should not be used in an untrusted or mission-critical environment.


Motivation
----------
Under the hood, Aquameta is a "datafied" web stack, built entirely in PostgreSQL.  The goal of the project is to reimagine the structure of a typical web framework as relational data so that everything under the hood is stored in the database, and all development, at an atomic level, is some form of data manipulation.


Core Extensions
---------------
Aquameta contains seven core PostgreSQL extensions, which together make up the web stack:

- [meta](src/pg-extension/meta) - Writable system catalog for PostgreSQL
- [bundle](src/pg-extension/bundle) - A version control system similar to git but for database rows intead of files
- [filesystem](src/pg-extension/filesystem) - A bi-directional file system integration system
- [event](src/pg-extension/event) - Pub/sub data change events API
- [endpoint](src/pg-extension/endpoint) - Maps PostgreSQL permissions and data acccess to the web, as well as allowing resource hosting and a web socket event server
- [widget](src/pg-extension/widget) - Modular web components that can be reused
- [semantics](src/pg-extension/semantics) - A metadata layer on top of the database schema, for binding columns and relations to widgets, decorating keys, etc.

Installation
------------
Aquameta is most easily installed on a Ubuntu 18 or Debian 9 instance; its installer manages dependencies by as `apt` packages.

To install, setup a clean Ubuntu 18 or Debian 9 instance.  You can run on bare metal, or using a virtual machine such as [VirtualBox](https://linuxhint.com/install_ubuntu_18-04_virtualbox/) on Mac OSX and Windows, or [KVM](https://linuxconfig.org/install-and-set-up-kvm-on-ubuntu-18-04-bionic-beaver-linux) on Linux.

Once your Linux machine is setup, acquire the Aquameta package by either downloading the latest [release](https://github.com/aquametalabs/aquameta/releases), or to try the bleeding edge version, clone the repository.  Then run the install script:

1. `git clone https://github.com/aquametalabs/aquameta.git`
2. `cd aquameta`
3. `./install.sh`
