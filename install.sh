#!/bin/bash
# exit on failure
set -e
set -o pipefail

#############################################################################
#
# Aquameta Installer Script
#
# Does the following:
# - install apt packages
# - install python packages
# - install postgresql extensions
# - 
#############################################################################

# prompting and sanity checking
echo "Aquameta 0.2 Installer Script"
echo "WARNING:"
echo "This code is highly experimental and should NOT be run in a production environment."

if [ "$1" != "--silent" ]
then
    read -p "Are you sure? " -n 1 -r
    echo    # (optional) move to a new line
    if ! [[ $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
fi

# set working directory and destination directory
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEST=/opt/aquameta

# make sure we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi



#############################################################################
# apt packages
#############################################################################

# update
apt-get update -y

# add the universe repository
apt-get install -y software-properties-common
add-apt-repository universe

# install required packages
apt-get install -y postgresql-10 postgresql-10-python-multicorn postgresql-server-dev-10 postgresql-plpython-10 python-pip python-werkzeug python-psycopg2 sendmail nginx sudo

# wget ca-certificates lsb-release git python python-pip python-dev nginx python-setuptools libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev pgxnclient fuse libfuse-dev supervisor



#############################################################################
# sendmail
#############################################################################

# locale-gen "en_US.UTF-8" && dpkg-reconfigure locales
# echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts



#############################################################################
# python packages
#############################################################################

# filesystem_fdw
cd $SRC/src/py-package/filesystem_fdw
sudo -H pip install --upgrade .

# aquameta-endpoint
cd $SRC/src/py-package/uwsgi-endpoint
sudo -H pip install --upgrade .

# pip install requests fusepy


#############################################################################
# aquameta postgresql extensions
#############################################################################

# install extensions into PostgreSQL's extensions/ directory
cd $SRC/src/pg-extension/meta && make && make install
cd $SRC/src/pg-extension/bundle && make && make install
cd $SRC/src/pg-extension/filesystem && make && make install
cd $SRC/src/pg-extension/email && make && make install
cd $SRC/src/pg-extension/event && make && make install
cd $SRC/src/pg-extension/endpoint && make && make install
cd $SRC/src/pg-extension/widget && make && make install
cd $SRC/src/pg-extension/semantics && make && make install



#############################################################################
# build the aquameta database
#############################################################################

# create aquameta database
sudo -u postgres createdb aquameta

# enable peer authentication
sudo sed -i "s/^local   all.*$/local all all trust/" /etc/postgresql/10/main/pg_hba.conf
systemctl restart postgresql.service

# create dependency extensions required by aquameta
echo "Installing dependencies..."
sudo -u postgres psql -c "create extension if not exists plpythonu" aquameta
sudo -u postgres psql -c "create extension if not exists multicorn schema public" aquameta
sudo -u postgres psql -c "create extension if not exists hstore schema public" aquameta
sudo -u postgres psql -c "create extension if not exists hstore_plpythonu schema public" aquameta
sudo -u postgres psql -c "create extension if not exists dblink schema public" aquameta
sudo -u postgres psql -c "create extension if not exists \"uuid-ossp\"" aquameta
sudo -u postgres psql -c "create extension if not exists pgcrypto schema public" aquameta

# create aquameta core extensions
echo "Installing core Aquameta extensions..."
sudo -u postgres psql -c "create extension meta" aquameta
sudo -u postgres psql -c "create extension bundle" aquameta
sudo -u postgres psql -c "create extension filesystem" aquameta
sudo -u postgres psql -c "create extension email" aquameta
sudo -u postgres psql -c "create extension event" aquameta
sudo -u postgres psql -c "create extension endpoint" aquameta
sudo -u postgres psql -c "create extension widget" aquameta
sudo -u postgres psql -c "create extension semantics" aquameta
sudo -u postgres psql -f $SRC/src/sql/ide/000-ide.sql aquameta



#############################################################################
# install and checkout enabled bundles
#############################################################################

mkdir --parents $DEST
cp -R $SRC/bundles-available $DEST
cp -R $SRC/bundles-enabled $DEST
chown -R postgres:postgres $DEST/bundles-available
chown -R postgres:postgres $DEST/bundles-enabled

echo "Loading bundles-enabled/*/*.csv ..."
for D in `find $DEST/bundles-enabled/* \( -type l -o -type d \)`
do
    sudo -u postgres psql -c "select bundle.bundle_import_csv('$D')" aquameta
done

echo "Checking out head commit of every bundle ..."
sudo -u postgres psql -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" aquameta


#############################################################################
# copy static htdocs to $DEST/htdocs
#############################################################################
cp -R $SRC/src/htdocs $DEST/
cp $SRC/src/pg-extension/widget/js/* $DEST/



#############################################################################
# grant default permissions for 'anonymous' and 'user' roles
#############################################################################

sudo -u postgres psql -f $SRC/src/sql/permissions.sql aquameta



#############################################################################
# configure uwsgi and start the service
#############################################################################

mkdir -p /etc/aquameta
# copy service file into /etc/systemd/system
cp $SRC/src/py-package/uwsgi-endpoint/aquameta.emperor.uwsgi.service /etc/systemd/system

# copy uwsgi .ini file into /etc/uwsgi/uwsgi-emperor.ini
cp $SRC/src/py-package/uwsgi-endpoint/uwsgi-emperor.ini /etc/aquameta

systemctl enable aquameta.emperor.uwsgi.service
systemctl start aquameta.emperor.uwsgi.service



#############################################################################
# configure nginx and restart the service
#############################################################################

cp $SRC/src/py-package/uwsgi-endpoint/nginx/aquameta_endpoint.conf /etc/nginx/sites-available
cd /etc/nginx/sites-enabled
rm -f ./default
ln -sf ../sites-available/aquameta_endpoint.conf
systemctl restart nginx



#############################################################################
# setup aquameta superuser
#############################################################################

echo "Superuser Registration"
echo "----------------------"
echo "Enter the name, email and password of the user you'd like to setup as superuser:"
read -p "Full Name: " NAME
read -p "Email Address: " EMAIL
read -s -p "Password: " PASSWORD

REG_COMMAND="select endpoint.register('$EMAIL', '$PASSWORD', true)"
sudo -u postgres psql -c "$REG_COMMAND" aquameta


#############################################################################
# finished!
#############################################################################

echo ""
echo ""
echo ""
echo "Aquameta was successfully installed.  Here are some starting places:"
echo "    - IDE: http://localhost/dev"
echo "    - Documentation: http://localhost/docs"
echo ""
echo ""

