aquameta
========

Aquameta is a web development environment where instead of storing code as flat
files in the file system, everything is stored in PostgreSQL as relational
data, including source code, html, css, javascript, images and other resources,
system configurations, database schema, permissions and more.  It has a
web-based IDE, and can be used to build web applications and much more.  For
more info, see [blog.aquameta.com](http://blog.aquameta.com/), espcially the [introduction](http://blog.aquameta.com/introducing-aquameta/).

Status
------

Aquameta is in early prototype stages, approaching version 0.2.  Do not use it in a
production, or untrusted environment.

Core Extensions
---------------

Aquameta contains seven core PostgreSQL extensions, which together make up the web stack:

- [meta](src/pg-extension/meta) - Writable system catalog for PostgreSQL
- [bundle](src/pg-extension/bundle) - A version control system similar to git but for database rows intead of files
- [filesystem](src/pg-extension/filesystem) - A bi-directional file system integration system
- [events](src/pg-extension/events) - Pub/sub data change events API
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


Development
-----------

To begin development, first login as the superuser you created during the Aquameta install at http://{your_ip}/login.
The primary development interface lives at http://{your_ip}/dev.
Create new Aquameta users at http://{your_ip}/register
Current Aquameta user info at http://{your_ip}/account
For more information, see the [documentation](docs/).

Contribute
----------

- Source Code: [github.com/aquametalabs/aquameta](https://github.com/aquametalabs/aquameta)
- Issue Tracker: [github.com/aquametalabs/aquameta/issues](https://github.com/aquametalabs/aquameta/issues)
- IRC: #aquameta on [freenode.net](http://freenode.net)

License
-------

The project is licensed under the GPL 3.0.
