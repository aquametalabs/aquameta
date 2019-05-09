aquameta
========

User Guide
----------

Aquameta is a web-based IDE for full-stack web development.  It allows the user to edit HTML, CSS, Javascript, database schema, views, templates, routes, tests and documentation, and do version control, branching, pushing, pulling, user management and permissions, all from a single web-based IDE.

* [demo video](https://www.youtube.com/watch?v=ZOpj8lvNJtg)
* [get started](docs/quickstart.md)
* [cheat sheet](docs/cheatsheet.md)
* [user documentation](docs/user.md)


Motivation
----------

Under the hood, Aquameta is a "datafied" web stack, a fairly radical departure from how most web stacks are architected.  It is built entirely in PostgreSQL.  Traditional web stacks are riddled with unnecessary complexity, because they lack an information model.  They *have structure*, but they don't make use of the very best tool to organize all those config files and templates and dependencies, namely the database.  Well, Aquameta does.

The goal of Aquameta is to reimplement the web stack using the database.  We have used the database to model countless domains and bring simplicity and coherences to vast complexity.  However, the traditional web stack remains quite complex and diverse.  Aquameta is a ground-up rebuild of each layer in the stack as relational data instead of files, and results in a vast decrease in complexity, and increase in modularity and reusability.

If this interests you, there's an [introduction](http://blog.aquameta.com/introducing-aquameta/) and more over on the [blog](http://blog.aquameta.com/).

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

From the installer, follow the instructions.


Contribute
----------

- Source Code: [github.com/aquametalabs/aquameta](https://github.com/aquametalabs/aquameta)
- Issue Tracker: [github.com/aquametalabs/aquameta/issues](https://github.com/aquametalabs/aquameta/issues)
- IRC: #aquameta on [freenode.net](http://freenode.net)
