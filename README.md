aquameta
========

Aquameta is a web-based development environment designed on the first principle
of datafication, and built entirely in PostgreSQL.

For more info, see [aquameta.org](http://aquameta.org/).

Status
------

Aquameta is in early prototype stages, version 0.1.

Core Modules
------------

- meta - Writable system catalog for PostgreSQL
- filesystem - A bi-directional file system integration system
- events - Pub/sub data change events API
- www - Maps PostgreSQL permissions and data acccess to the web, as well as allowing resource hosting and a web socket event server
- bundle - A version control system similar to git but for database rows intead of files
- widget - Modular web components that can be reused
- p2p - peer-to-peer communication between Aquameta nodes

Installation
------------

If you want to give Aquameta a try at this early stage, feel free.  Aquameta is
easiest to install on a isolated Linux instance such as an AWS EC2 or Docker
container, running Ubuntu 14.04 or greater.  In this environment, just run the
`install.sh` script and Aquameta and it's dependencies will be installed.  

In other environments however, we recommend going through that install script
and translating and sanity-checking any commands.  For example, if your system
is not an apt-based OS, you'll have to translate the package installs into
whatever packaging system (like Brew) you might be using.

Contribute
----------

- Issue Tracker: [github.com/aquametalabs/aquameta/issues](http://github.com/aquametalabs/aquameta/issues)
- Source Code: [github.com/aquametalabs/aquameta](github.com/aquametalabs/aquameta)

Support
-------

If you are having issues, please let us know.
We have a mailing list located at: aquameta-discuss@google-groups.com

License
-------

The project is licensed under the GPL.
