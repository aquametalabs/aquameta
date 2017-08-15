#!/bin/bash
# exit on failure
set -e
set -o pipefail


#############################################################################
# Prompting and sanity checking
#############################################################################

echo "Aquameta 0.1 Installer Script"
echo "This script should be run on an Ubuntu Linux server instance, 14.04 or greater."
echo "This code is highly experimental and should NOT be run in a production environment."

if [ $0 = '--silent' ]
then
    read -p "Are you sure? " -n 1 -r
    echo    # (optional) move to a new line
    if ! [[ $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
fi

# make sure we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi



# make sure this script is being run in /s/aquameta
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ "$DIR" != "/s/aquameta" ]]; then
   echo "This script should be run from /s/aquameta"
   exit 1
fi

#############################################################################
# Apt package installs
#############################################################################

apt-get update -y && apt-get install -y wget ca-certificates lsb-release git python python-pip python-dev nginx python-setuptools sudo libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev pgxnclient fuse libfuse-dev sendmail supervisor


#############################################################################
# Install postgresql 9.6 from source, with support for perl, python, etc.
# Then install some extensions and required python modules.
# TODO:  Add plv8, java?
#############################################################################

cd /tmp
wget https://ftp.postgresql.org/pub/source/v9.6.0/postgresql-9.6.0.tar.gz
tar -zxvf postgresql-9.6.0.tar.gz
cd postgresql-9.6.0
./configure --prefix=/usr/local --enable-nls --with-perl --with-python --with-openssl --with-ossp-uuid --with-libxml
make world
make install-world
adduser --gecos "Postgresql" --disabled-password --no-create-home --disabled-login postgres
# log dir
mkdir --parents /var/log/postgresql
chown -R postgres:postgres /var/log/postgresql
# socket dir
mkdir --parents /var/run/postgresql
chown -R postgres:postgres /var/run/postgresql
# data dir
mkdir --parents /var/lib/postgresql/aquameta
chown -R postgres:postgres /var/lib/postgresql/aquameta
sudo -u postgres /usr/local/bin/initdb -D /var/lib/postgresql/aquameta
# TODO: audit this...
sed -i "s/^local   all.*$/local all all trust/" /var/lib/postgresql/aquameta/pg_hba.conf
echo "host all  all 0.0.0.0/0  md5"   >> /var/lib/postgresql/aquameta/pg_hba.conf
echo "listen_addresses='*'" >> /var/lib/postgresql/aquameta/postgresql.conf
echo "unix_socket_directories = '/tmp,/var/run/postgresql'" >> /var/lib/postgresql/aquameta/postgresql.conf

# start the server
sudo -u postgres /usr/local/bin/pg_ctl -D /var/lib/postgresql/aquameta -l /var/log/postgresql/postgresql.log start

# Install some cool PostgreSQL extensions and python modules
pgxn install multicorn
pgxn install pgtap
pip install --upgrade pip
pip install requests fusepy


#############################################################################
# Configure sendmail - used to send registration emails
#############################################################################
locale-gen "en_US.UTF-8" && dpkg-reconfigure locales
echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts


#############################################################################
# uwsgi emperor
#############################################################################
# build the aquameta db python egg
cd $DIR/core/004-http_server/servers/uwsgi
pip install .
uwsgi --die-on-term --emperor $DIR/core/004-http_server/servers/uwsgi/conf/uwsgi/aquameta_db.ini &

#############################################################################
# nginx server
#############################################################################
# setup /etc/nginx settings
cp $DIR/core/004-http_server/servers/uwsgi/conf/nginx/aquameta_endpoint.conf /etc/nginx/sites-available
cd /etc/nginx/sites-enabled
rm ./default
ln -s ../sites-available/aquameta_endpoint.conf
/etc/init.d/nginx restart


#############################################################################
# setup pgfs (optional)
#############################################################################
# mkdir /mnt/aquameta


#############################################################################
# build aquameta
#############################################################################
echo "create role root superuser login;" | psql -U postgres postgres

# we're doing this for 0.1 version only!  remove this when we build a permissions UI
echo "create role anonymous login superuser" | psql -U postgres postgres
createdb aquameta

cd $DIR

echo "Loading requirements ..."
cat core/requirements.sql | psql aquameta

echo "Loading core/*.sql ..."
cat core/0*/0*.sql  | psql aquameta

echo "Loading bundles-enabled/*.sql ..."
cat bundles-enabled/*.sql | psql aquameta

echo "Checking out head commit of every bundle ..."
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta

echo "Loading default permissions..."
cat core/004-http_server/default_permissions.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

# Install FS FDW
cd $DIR/core/002-filesystem/fs_fdw
pip install . --upgrade
cat fs_fdw.sql | psql aquameta


echo ""
echo ""
echo ""
echo "Aquameta was successfully installed.  Here are some starting places:"
echo "    - IDE: http://localhost/ide"
echo "    - Documentation: http://localhost/docs"

