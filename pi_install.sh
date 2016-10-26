apt-get update -y && apt-get install -y wget ca-certificates lsb-release git python python-pip python-dev nginx python-setuptools sudo libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev #upervisor



#################### install postgresql 9.6 from source ####################
cd /tmp
wget https://ftp.postgresql.org/pub/source/v9.6.0/postgresql-9.6.0.tar.gz
tar -zxvf postgresql-9.6.0.tar.gz
cd postgresql-9.6.0
# alternate location?
./configure --enable-nls --with-perl --with-python --with-openssl --with-ossp-uuid --with-libxml
make world
make install-world

adduser postgres

mkdir /usr/local/pgsql/data
mkdir /var/log/postgresql
chown postgres:postgres /usr/local/pgsql/data
chown postgres:postgres /var/log/postgresql

su - postgres
echo 'set PATH=$PATH:/usr/local/pgsql/bin' >> ~/.bash_profile
/usr/local/pgsql/bin/initdb -D /usr/local/pgsql/data
/usr/local/pgsql/bin/pg_ctl -D /usr/local/pgsql/data -l /var/log/postgresql/postgresql.log start

exit

apt-get install -y pgxnclient fuse libfuse-dev sendmail
# needs pg_config but not in $PATH yet
pgxn install multicorn
pgxn install pgtap
pip install requests sphinx sphinx-autobuild fusepy
locale-gen "en_US.UTF-8" && dpkg-reconfigure locales

# FQDN for sendmail
echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts

#################### nginx/uwsgi server ###############################
# setup /etc/nginx settings
cd /etc/nginx/sites-available
cp /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi/conf/nginx/aquameta_endpoint.conf .

cd /etc/nginx/sites-enabled
rm ./default && \
        ln -s ../sites-available/aquameta_endpoint.conf


# build the aquameta db python egg
cd /s/aquameta/core/004-aquameta_endpoint/servers/uwsgi
pip install .


# ADD docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

## pgfs
mkdir /mnt/aquameta


#################### build aquameta ###############################
su - postgres
cd /s/aquameta

createdb aquameta
./build.sh # insert rest of build.sh script here?

# audit this...
echo "host all  all 0.0.0.0/0  md5"   >> /etc/postgresql/9.5/main/pg_hba.conf
sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/9.5/main/pg_hba.conf
echo "listen_addresses='*'" >> /etc/postgresql/9.5/main/postgresql.conf
psql -c "alter role postgres password 'postgres'" aquameta

# Install pgtap
# RUN psql -c "create extension pgtap" aquameta
exit

# Install FS FDW
cd /s/aquameta/core/002-filesystem/fs_fdw
pip install . --upgrade
cat fs_fdw.sql | psql -a -U postgres aquameta
