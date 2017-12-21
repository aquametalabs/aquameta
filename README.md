aquameta
========

Aquameta is a web development environment where instead of storing code as flat
files in the file system, everything is stored in PostgreSQL as relational
data, including source code, html, css, javascript, images and other resources,
system configurations, database schema, permissions and more.  It has a
web-based IDE, and can be used to build web applications and much more.  For
more info, see [aquameta.org](http://aquameta.org/).

Status
------

Aquameta is in early prototype stages, version 0.1.  Do not use it in a
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

Aquameta can be installed either via Docker (very easy) or from source (very difficult).

### Docker

To install via Docker, the easiest way is to just pull down the latest image from Docker Hub:

```
docker pull aquametalabs/aquameta:0.1.0-rc1
```

Alternately, you can clone the Aquameta git repository and build your own Docker image (which takes about 15 minutes):

```
git clone https://github.com/aquametalabs/aquameta.git
cd aquameta/
docker build -t aquametalabs/aquameta .
```

Once you've either pulled or built a Aquameta image, run the container to start it up:

```
docker run -dit -p 80:80 -p 5432:5432 --privileged aquametalabs/aquameta:0.1.0-rc1
```

If you wish to use alternate ports, they can be changed in the `docker run` command.

```
# run the Aquameta webserver on port 8080, and the PostgreSQL server on port 5433
sudo docker run -dit -p 8080:80 -p 5433:5432 --privileged aquametalabs/aquameta:0.1.0-rc1
```

Make a note of the container-id that this command outputs.  You can use it to
restart the container later, if you restart your computer, to get your data back.

Once Aquameta is running, browse to `http://localhost/dev` (or whatever
host/port it is installed on) to access the web-based IDE.  To access the
PostgreSQL database, use `psql -p 5432 aquameta`.

Aquameta uses the "long-running container" pattern instead of exporting volumes
at this time, so if you stop the container, just restart it with `docker
restart {container_id}`.


### From Source (DIFFICULT)

To install Aquameta from source, follow the steps in the
[install.sh](https://github.com/aquametalabs/aquameta/blob/master/install.sh)
script.  The script is designed to run on an Ubuntu 16.04 server, and will
require some adaptation for different environments.

Contribute
----------

- Source Code: [github.com/aquametalabs/aquameta](https://github.com/aquametalabs/aquameta)
- Issue Tracker: [github.com/aquametalabs/aquameta/issues](https://github.com/aquametalabs/aquameta/issues)
- IRC Channel: `#aquameta` on `irc.freenode.net`

Support
-------

If you are having issues, please let us know.
We have a mailing list located at: aquameta-discuss@googlegroups.com

License
-------

The project is licensed under the GPL.
