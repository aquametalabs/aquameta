FROM ubuntu:latest
MAINTAINER Eric Hanson <eric@aquameta.com>

# to build: 
#   docker build -t aquametalabs/aquameta .
#
# to run:
#   docker run -dit -p 80:80 -p 8080:8080 -p 5432:5432 aquametalabs/aquameta
#                      ^uwsgi  ^bg_worker    ^postgres
#
# access PostgreSQL (password 'postgres') with:
#   psql -h localhost -p 5432 -U postgres aquameta
#
# access the ide by browsing to port 8080 of the host machine.

ENV REFRESHED_AT 2015-11-10

RUN apt-get update -y && apt-get install -y wget ca-certificates lsb-release git build-essential cmake zlib1g-dev libssl-dev python python-pip python-dev nginx
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y postgresql-9.4 postgresql-plpython-9.4 postgresql-server-dev-9.4 pgxnclient
RUN pip install psycopg2 werkzeug
RUN pgxn install multicorn

RUN mkdir -p /s/aquameta


##################### BACKGROUND WORKER HTTP SERVER ##########################


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






#################### UWSGI ###############################


# build the aquameta db python egg
ADD core/004-aquameta_endpoint/servers/uwsgi /srv/uwsgi
RUN cd /srv/uwsgi && python setup.py sdist

# before last step, need to fix aquameta_db.ini via https://github.com/StefanoOrdine/uwsgi-docs/commit/1490026103fd7f4f1dd4e78911daac59c55f89b5
RUN cd /tmp && wget http://projects.unbit.it/downloads/uwsgi-2.0.11.2.tar.gz && tar -zxvf uwsgi-2.0.11.2.tar.gz && cd uwsgi-2.0.11.2 && python uwsgiconfig.py --build /srv/uwsgi/conf/uwsgi/aquameta_db_build.ini && mkdir /srv/bin && mv ./uwsgi /srv/bin/





EXPOSE 80 8080 5432

USER postgres
RUN /etc/init.d/postgresql start && cd /s/aquameta && ./build.sh && echo "alter role postgres password 'postgres';" | psql aquameta

VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]



# ENTRYPOINT /usr/lib/postgresql/9.4/bin/postgres -D /var/lib/postgresql/9.4/main -c config_file=/etc/postgresql/9.4/main/postgresql.conf

ADD docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT ["/usr/bin/supervisord"]

# RUN /srv/bin/uwsgi --die-on-term --emperor /srv/uwsgi/conf/uwsgi

