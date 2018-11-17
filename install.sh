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

# set working directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# make sure we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi



#############################################################################
# apt packages
#############################################################################

sudo add-apt-repository universe
apt-get update 
apt-get install postgresql-10 postgresql-10-python-multicorn postgresql-server-dev-10 postgresql-plpython-10 python-pip python-werkzeug python-psycopg2 sendmail nginx

# wget ca-certificates lsb-release git python python-pip python-dev nginx python-setuptools sudo libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev pgxnclient fuse libfuse-dev sendmail supervisor



#############################################################################
# sendmail
#############################################################################

# locale-gen "en_US.UTF-8" && dpkg-reconfigure locales
# echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts



#############################################################################
# python packages
#############################################################################

# filesystem_fdw
cd $DIR/src/py-package/filesystem_fdw
pip install .

# aquameta-endpoint
cd $DIR/src/py-package/uwsgi-endpoint
pip install .



#############################################################################
# aquameta postgresql extensions
#############################################################################

# install extensions into PostgreSQL's extensions/ directory
cd $DIR/src/pg-extension/meta && make && make install
cd $DIR/src/pg-extension/bundle && make && make install
cd $DIR/src/pg-extension/filesystem && make && make install
cd $DIR/src/pg-extension/email && make && make install
cd $DIR/src/pg-extension/event && make && make install
cd $DIR/src/pg-extension/endpoint && make && make install
cd $DIR/src/pg-extension/widget && make && make install



#############################################################################
# build the aquameta database
#############################################################################

# create aquameta database
sudo -u postgres createdb aquameta

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



#############################################################################
# install and checkout enabled bundles
#############################################################################

echo "Loading bundles-enabled/*/*.csv ..."
for D in `find $DIR/bundles-enabled/* \( -type l -o -type d \)`
do
    sudo -u postgres psql -c "select bundle.bundle_import_csv('$D')" aquameta
done

echo "Checking out head commit of every bundle ..."
sudo -u postgres psql -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" aquameta


#############################################################################
# grant default permissions for 'anonymous' and 'user' roles
#############################################################################
sudo -u postgres psql -f $DIR/permissions.sql aquameta



#############################################################################
# configure uwsgi and start the service
#############################################################################
mkdir -p /etc/aquameta
# copy service file into /etc/systemd/system
cp $DIR/src/py-package/uwsgi-endpoint/aquameta.emperor.uwsgi.service /etc/systemd/system

# copy uwsgi .ini file into /etc/uwsgi/uwsgi-emperor.ini
cp $DIR/src/py-package/uwsgi-endpoint/uwsgi-emperor.ini /etc/aquameta

systemctl start aquameta.emperor.uwsgi.service



#############################################################################
# configure nginx and restart the service
#############################################################################
# setup /etc/nginx settings
# cp $DIR/extensions/py-package/uwsgi-endpoint/conf/nginx/aquameta_endpoint.conf /etc/nginx/sites-available
# cd /etc/nginx/sites-enabled
# rm ./default
# ln -s ../sites-available/aquameta_endpoint.conf
# /etc/init.d/nginx restart


# uwsgi --die-on-term --emperor $DIR/extensions/endpoint/servers/uwsgi/conf/uwsgi/aquameta_db.ini &


# chown -R postgres:postgres /s/aquameta/bundles-available/*.*.*


# pgxn install pgtap
# pip install requests fusepy


echo ""
echo ""
echo ""
echo "Aquameta was successfully installed.  Here are some starting places:"
echo "    - IDE: http://localhost/dev"
echo "    - Documentation: http://localhost/docs"
echo ""
echo ""

