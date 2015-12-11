FROM ubuntu:latest
MAINTAINER Eric Hanson <eric@aquameta.com>

# to build: 
#   docker build -t aquametalabs/aquameta .
#
# to run:
#   docker run -dit -p 8080:8080 -p 5432:5432 aquametalabs/aquameta
#
# access PostgreSQL (password 'postgres') with:
#   psql -h localhost -p 5432 -U postgres aquameta
#
# access the ide by browsing to port 8080 of the host machine.

ENV REFRESHED_AT 2015-11-10

RUN apt-get update -y && apt-get install -y wget ca-certificates lsb-release git build-essential cmake zlib1g-dev libssl-dev python python-pip python-dev
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y postgresql-9.4 postgresql-plpython-9.4 postgresql-server-dev-9.4

RUN mkdir -p /s/aquameta

# web sockets
RUN cd /s && git clone https://github.com/qpfiffer/libwebsockets.git && \
    cd libwebsockets && mkdir build && cd build && cmake .. && make && make install && \
    cd /usr/lib && ln -s /usr/local/lib/libwebsockets.so.5.0.0

# add aquameta (assuming we're building this from cwd)
ADD . /s/aquameta/
RUN cd /s/aquameta/core/004-aquameta_endpoint/servers/background_worker && make && make install

#Add the following line is in your postgresql.conf:
#shared_preload_libraries = 'pg_http'
RUN sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'pg_http'/" /etc/postgresql/9.4/main/postgresql.conf

# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.4/main/pg_hba.conf

# And add ``listen_addresses`` to ``/etc/postgresql/9.4/main/postgresql.conf``
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.4/main/postgresql.conf


EXPOSE 8080 5432

USER postgres
RUN /etc/init.d/postgresql start && cd /s/aquameta && ./build.sh && echo "alter role postgres password 'postgres';" | psql aquameta

VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

ENTRYPOINT /usr/lib/postgresql/9.4/bin/postgres -D /var/lib/postgresql/9.4/main -c config_file=/etc/postgresql/9.4/main/postgresql.conf
