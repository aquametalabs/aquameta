FROM ubuntu:latest
MAINTAINER Eric Hanson <eric@aquameta.com>

# to build:
#   docker build -t aquametalabs/aquameta .
#
# to run:
#   docker run -dit -p 80:80 -p 5432:5432 --privileged aquametalabs/aquameta
#                      ^uwsgi   ^postgres   ^fuse
#
# access PostgreSQL (password 'postgres') with:
#   psql -h localhost -p 5432 aquameta
#
# access the ide by browsing to port 80 of the host machine.

ENV REFRESHED_AT 2018-11-19

# copy the repo to /tmp
RUN mkdir -p /tmp/aquameta
COPY . /tmp/aquameta/


USER root
WORKDIR /tmp/aquameta
RUN ./install.sh --silent


EXPOSE 80 5432
# VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]
# ENTRYPOINT ["/usr/bin/supervisord"]

