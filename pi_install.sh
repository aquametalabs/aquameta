apt-get update -y && apt-get install -y wget ca-certificates lsb-release git python python-pip python-dev nginx supervisor python-setuptools sudo libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev

wget https://ftp.postgresql.org/pub/source/v9.6.0/postgresql-9.6.0.tar.gz
tar -zxvf postgresql-9.6.0.tar.gz
cd postgresql-9.6.0
./configure --enable-nls --with-perl --with-python --with-openssl --with-ossp-uuid --with-libxml
make world
make install-world
adduser postgres
mkdir /usr/local/pgsql/data
su - postgres
echo 'set PATH=$PATH:/usr/local/pgsql/bin' >> ~/.bash_profile
/usr/local/pgsql/bin/initdb -D /usr/local/pgsql/data
# start the server here...?
createdb test
install pgxnclient fuse libfuse-dev sendmail
pgxn install multicorn
pgxn install pgtap
pip install requests sphinx sphinx-autobuild fusepy
locale-gen "en_US.UTF-8" && dpkg-reconfigure locales


# cp the repo to /s
RUN mkdir -p /s/aquameta
ADD . /s/aquameta/


# FQDN for sendmail
RUN echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts



#################### nginx/uwsgi server ###############################
# setup /etc/nginx settings
WORKDIR /etc/nginx/sites-available
RUN cp /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi/conf/nginx/aquameta_endpoint.conf .

WORKDIR /etc/nginx/sites-enabled
RUN rm ./default && \
        ln -s ../sites-available/aquameta_endpoint.conf


# build the aquameta db python egg
WORKDIR /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi
RUN pip install .


ADD docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

## pgfs
RUN mkdir /mnt/aquameta


#################### build aquameta ###############################
USER postgres
WORKDIR /s/aquameta
RUN echo "host all  all 0.0.0.0/0  md5"   >> /etc/postgresql/9.5/main/pg_hba.conf && \
	sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/9.5/main/pg_hba.conf && \
	echo "listen_addresses='*'" >> /etc/postgresql/9.5/main/postgresql.conf && \
	/etc/init.d/postgresql start && \
	./build.sh && \
	psql -c "alter role postgres password 'postgres'" aquameta

# Install pgtap
# RUN psql -c "create extension pgtap" aquameta

# Install FS FDW
USER root
WORKDIR /s/aquameta/core/002-filesystem/fs_fdw
RUN pip install . --upgrade && \
	/etc/init.d/postgresql start && \
	cat fs_fdw.sql | psql -a -U postgres aquameta 2>&1 && \
	/etc/init.d/postgresql stop


#################### docker container ###############################
# finally, setup our container
USER root
WORKDIR /s/aquameta
EXPOSE 80 5432
# VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]
ENTRYPOINT ["/usr/bin/supervisord"]

