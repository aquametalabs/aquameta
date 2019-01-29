aquameta
========

Aquameta is a web development environment where instead of storing code as flat
files in the file system, everything is stored in PostgreSQL as relational
data, including source code, html, css, javascript, images and other resources,
system configurations, database schema, permissions and more.  It has a
web-based IDE, and can be used to build web applications and much more.  For
more info, see [blog.aquameta.com](http://blog.aquameta.com/), espcially the [introduction](http://blog.aquameta.com/2015/08/28/introducing-aquameta/).

Status
------

Aquameta is in early prototype stages, approaching version 0.2.  Do not use it in a
production, or untrusted environment.

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

Aquameta is designed for installation on a Ubuntu 18.04 instance.  Aquameta installs a number of `apt` packages.  It works best on a clean install of Ubuntu.  We recommend using a KVM instance, or Amazon EC2 instance.

1. `git clone https://github.com/aquametalabs/aquameta.git`
2. `cd aquameta`
3. `./install.sh`

From the installer, follow the instructions.


Development
-----------

The primary development interface lives at http://{your_ip}/dev.  From here you can create bundles and edit their contents.  For more information, see the [documentation](docs/).

Contribute
----------

- Source Code: [github.com/aquametalabs/aquameta](https://github.com/aquametalabs/aquameta)
- Issue Tracker: [github.com/aquametalabs/aquameta/issues](https://github.com/aquametalabs/aquameta/issues)

License
-------

The project is licensed under the GPL 3.0.
