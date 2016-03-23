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
#   psql -h localhost -p 5432 -U postgres aquameta
#
# access the ide by browsing to port 80 of the host machine.

ENV REFRESHED_AT 2015-11-10

RUN apt-get update -y && apt-get install -y wget ca-certificates lsb-release git python python-pip python-dev nginx supervisor python-setuptools
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y postgresql-9.5 postgresql-plpython-9.5 postgresql-server-dev-9.5 pgxnclient fuse libfuse-dev
RUN pgxn install multicorn pgtap
RUN pip install requests sphinx sphinx-autobuild fusepy
RUN locale-gen "en_US.UTF-8" && dpkg-reconfigure locales


# cp the repo to /s
RUN mkdir -p /s/aquameta
ADD . /s/aquameta/





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

## Docker
RUN mkdir /mnt/aquameta

#################### build aquameta ###############################
USER postgres
RUN echo "host all  all 0.0.0.0/0  md5"   >> /etc/postgresql/9.5/main/pg_hba.conf && \
	sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/9.5/main/pg_hba.conf && \
	echo "listen_addresses='*'" >> /etc/postgresql/9.5/main/postgresql.conf && \
	/etc/init.d/postgresql start && \
	cd /s/aquameta && \
	./build.sh && \
	psql -c "alter role postgres password 'postgres'" aquameta && \
	/etc/init.d/postgresql stop



#################### docker container ###############################
# finally, setup our container
USER root
EXPOSE 80 8080 5432
# VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]
ENTRYPOINT ["/usr/bin/supervisord"]

