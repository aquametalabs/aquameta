aquameta
========

Overview
--------
Aquameta is a web-based IDE for full-stack web development.  Developers can manage HTML, CSS, Javascript, database schema, views, templates, routes, tests and documentation, and do version control, branching, pushing, pulling, user management and permissions, all from a single web-based IDE.  In theory.  And mostly in practice.

Under the hood, Aquameta is a "datafied" web stack, built entirely in PostgreSQL.  The structure of a typical web framework is represented in Aquameta as big database schema with 6 PostgreSQL schemas containing ~60 tables, ~50 views and ~90 stored procedures.  Apps developed in Aquameta are represented entirely as relational data, and all development, at an atomic level, is some form of data manipulation.  Also in theory.  And mostly in practice.

<!--
* [introduction](http://blog.aquameta.com/introducing-aquameta/)
* [blog](http://blog.aquameta.com/) / [twitter](http://twitter.com/aquameta) / [youtube](https://www.youtube.com/user/bigcountry503/videos) / [twitch](http://twitch.tv/aquameta)
-->

* [FLOSS TWiT.tv intro](https://www.youtube.com/watch?v=G0C8AsXNPAU)
* [demo video](https://www.youtube.com/watch?v=ZOpj8lvNJtg)
* [get started](docs/quickstart.md)
* [cheat sheet](docs/cheatsheet.md)


Status
------
Aquameta is an experimental project, still in early stages of development.  It is not suitable for production development and should not be used in an untrusted or mission-critical environment.


Core Extensions
---------------
Aquameta contains seven core PostgreSQL extensions, which together make up the web stack:

- [meta](https://github.com/aquametalabs/meta) - Writable system catalog for PostgreSQL
- [bundle](src/pg-extension/bundle) - A version control system similar to git but for database rows instead of files
- [filesystem](src/pg-extension/filesystem) - A bi-directional file system integration system
- [event](src/pg-extension/event) - Pub/sub data change events API
- [endpoint](src/pg-extension/endpoint) - REST endpoint handler plus resource hosting, templates and a WebSocket event server
- [widget](src/pg-extension/widget) - Modular web user interface components made of HTML, CSS and Javascript
- [semantics](src/pg-extension/semantics) - A metadata layer on top of the database schema, for binding columns and relations to widgets, decorating keys, etc.


Installation
------------
Aquameta is most easily installed on a Ubuntu 18 or Debian 9 instance; its installer manages dependencies by as `apt` packages.

To install, setup a clean Ubuntu 18 or Debian 9 instance.  You can run on bare metal, or using a virtual machine such as [VirtualBox](https://linuxhint.com/install_ubuntu_18-04_virtualbox/) on Mac OSX and Windows, or [KVM](https://linuxconfig.org/install-and-set-up-kvm-on-ubuntu-18-04-bionic-beaver-linux) on Linux.

Once your Linux machine is setup, acquire the Aquameta package by either downloading the latest [release](https://github.com/aquametalabs/aquameta/releases), or to try the bleeding edge version, clone the repository.  Then run the install script:

1. `git clone https://github.com/aquametalabs/aquameta.git`
2. `cd aquameta`
3. `./install.sh`


About
-----
Aquameta has been the life project of Eric Hanson for close to 20 years off-and-on.  Functional prototypes have been developed in XML, RDF and MySQL, but PostgreSQL is the first database discovered that has the functionality necessary to achieve something close to practical, and huge advances in web technology like WebRTC, ES6 modules, and more have shown some light at the end of the tunnel.

Technical goals of the project include:
- Allow complete management of the database using only INSERT, UPDATE and DELETE commands (expose the DDL as DML)
- Version control of relational data
- Reified architecture, where the entire system is self-defined as data, and as such can evolve using only data manipulation
- Remote push/pull of commits to relational VCS
- Access and manipulate the database as a file system from the command prompt
- Access and manipulate the file system as relational data from the SQL prompt
- Internal event system for pub/sub of changes to tables, columns or rows
- Modular web interface components ("widgets") made of HTML, CSS, Javascript, that are self-contained, manage their own dependencies, accept input arguments, can instantiate other widgets, and can emit events that other widgets can subscribe to
- "Semantic decoration" allows the user to associate UI components with schema components (relations, columns, data types), auto-generate simple CRUD UIs, and progressively enhance a UI by overriding sensible defaults with custom widgets
- Pub/sub notification let peers download new content from each other as it comes available without polling
- Users communicate with each other by exchanging structured, relational data
- Decentralized P2P network with no single point of failure
- Decentralize the web
- Deprecate the file system

Human goals
- Teach people to speak the language of data
- Convert word-based knowledge and information to structured knowledge and information
- Stretch a net of approximate categorization across our earth
