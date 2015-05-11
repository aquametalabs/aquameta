FROM ubuntu:latest
MAINTAINER Eric Hanson <eric@aquameta.com>

# to build: 
#   docker build -t aquameta .
#
# to run:
#   docker run -it -p 8080:8080 aquameta

ENV REFRESHED_AT 2015-02-23

RUN apt-get update -y && apt-get install -y wget ca-certificates lsb-release git build-essential cmake zlib1g-dev libssl-dev
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y postgresql-9.4

RUN mkdir -p /s/aquameta

# web sockets
RUN cd /s && git clone https://github.com/qpfiffer/libwebsockets.git && \
    cd libwebsockets && mkdir build && cd build && cmake .. && make && make install

# add aquameta (assuming we're building this from cwd)
ADD . /s/aquameta/
RUN cd aquameta/http/background_worker && make && make install

# create extension
#RUN echo "create extension pg_http" | psql
# createdb aquameta
#Add the following line is in your postgresql.conf:
#shared_preload_libraries = 'pg_http'
#cat sql/0*.sql|psql aquameta

# XXX set unpriv'd user

EXPOSE 8080
#ENTRYPOINT 
