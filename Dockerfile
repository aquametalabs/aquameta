FROM ubuntu:latest
MAINTAINER Eric Hanson <eric@aquameta.com>

# to build:
#   docker build -t aquametalabs/aquameta .
#
# to run:
#   docker run -dit -p 80:80 -p 8080:8080 -p 5432:5432 --privilaged aquametalabs/aquameta
#                      ^uwsgi   ^bg_worker   ^postgres   ^ fuse
#
# access PostgreSQL (password 'postgres') with:
#   psql -h localhost -p 5432 -U postgres aquameta
#
# access the ide by browsing to port 8080 of the host machine.

ENV REFRESHED_AT 2015-11-10

RUN apt-get update -y && apt-get install -y wget ca-certificates lsb-release git build-essential cmake zlib1g-dev libssl-dev python python-pip python-dev nginx supervisor
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y postgresql-9.4 postgresql-plpython-9.4 postgresql-server-dev-9.4 pgxnclient fuse libfuse-deb
RUN pgxn install multicorn
RUN pip install requests sphinx sphinx-autobuild fusepy


# cp the repo to /s
RUN mkdir -p /s/aquameta
ADD . /s/aquameta/


############## BACKGROUND WORKER HTTP SERVER ##########################
# web sockets
RUN cd /tmp && git clone https://github.com/qpfiffer/libwebsockets.git && \
    cd libwebsockets && mkdir build && cd build && cmake .. && make && make install && \
    cd /usr/lib && ln -s /usr/local/lib/libwebsockets.so.5.0.0

# add aquameta (assuming we're building this from cwd)
RUN cd /s/aquameta/core/004-aquameta_endpoint/servers/background_worker && make && make install

#shared_preload_libraries = 'pg_http'
RUN sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'pg_http'/" /etc/postgresql/9.4/main/postgresql.conf





#################### nginx/uwsgi server ###############################
# setup /etc/nginx settings
RUN cd /etc/nginx/sites-available && \
        cp /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi/conf/nginx/aquameta_endpoint.conf . && \
        cd ../sites-enabled && \
        rm ./default && \
        ln -s ../sites-available/aquameta_endpoint.conf


# build the aquameta db python egg
RUN cd /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi && pip install .

ADD docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

#################### build aquameta ###############################
USER postgres
RUN echo "host all  all 0.0.0.0/0  md5"   >> /etc/postgresql/9.4/main/pg_hba.conf && \
	sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/9.4/main/pg_hba.conf && \
	echo "listen_addresses='*'" >> /etc/postgresql/9.4/main/postgresql.conf && \
	/etc/init.d/postgresql start && \
	cd /s/aquameta && \
	./build.sh && \
	psql -c "alter role postgres password 'postgres'" aquameta && \
	psql -c "create role guest superuser login" aquameta && \
	/etc/init.d/postgresql stop

## Docker
RUN mkdir /mnt/aquameta



#################### docker container ###############################
# finally, setup our container
USER root
EXPOSE 80 8080 5432
# VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]
ENTRYPOINT ["/usr/bin/supervisord"]

