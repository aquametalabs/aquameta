#!/bin/bash
# exit on failure
set -e
set -o pipefail

echo "path: $PATH"

#############################################################################
#
# Aquameta Installer Script
#
# Does the following:
# - install apt packages
# - install python packages
# - install postgresql extensions
#
#############################################################################

# prompting and sanity checking
echo "                                           __          "
echo "_____    ________ _______    _____   _____/  |______   "
echo "\__  \  / ____/  |  \__  \  /     \_/ __ \   __\__  \  "
echo " / __ \< <_|  |  |  // __ \|  Y Y  \  ___/|  |  / __ \_"
echo "(____  /\__   |____/(____  /__|_|  /\___  >__| (____  /"
echo "     \/    |__|          \/      \/     \/          \/ "
echo "            [ version 0.3.0 - base install ]"
echo ""
echo "                 OBLIGATORY WARNING:"
echo ""
echo "    This code is highly experimental and should "
echo "       NOT be run in a production environment."
echo "              You have been warned."
echo "                     ❤ MGMT."

read -p "Continue? [y/N]" -n 1 -r
echo    # (optional) move to a new line
if ! [[ $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

# set working directory and destination directory
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# make sure we're running as root
#if [[ $EUID -ne 0 ]]; then
#   echo "This script must be run as root"
#   exit 1
#fi



#############################################################################
# prompt for $DEST location
#############################################################################
read -p "Installation directory [$SRC]: " DEST
DEST=${DEST:-$SRC}



#############################################################################
# aquameta postgresql extensions
#############################################################################

# install extensions into PostgreSQL's extensions/ directory
echo "Building core PostgreSQL extensions..."
cd $SRC/extensions/pg_catalog_get_defs && make && make install
cd $SRC/extensions/meta && make && make install
cd $SRC/extensions/bundle && make && make install
cd $SRC/extensions/event && make && make install
# build the plgo part of extension
# (disabled because for now we're just not using templates)
# cd $SRC/src/pg-extension/endpoint/endpoint && /home/eric/go/bin/plgo . && \
#     cp build/endpoint.so .. && \
#     cp build/endpoint.h .. && \
#     cp build/endpoint--0.1.sql ../003-plgo.sql
# cd $SRC/extensions/endpoint && make && make install with_llvm=no
cd $SRC/extensions/endpoint && make && make install
cd $SRC/extensions/widget && make && make install
cd $SRC/extensions/semantics && make && make install



#############################################################################
# build the aquameta database
#############################################################################

# create dependency extensions required by aquameta
echo "Installing dependency extensions..."
# sudo -u postgres psql -c "create extension if not exists plpython3u" aquameta
# sudo -u postgres psql -c "create extension if not exists multicorn schema public" aquameta
sudo -u postgres psql -c "create extension if not exists hstore schema public" aquameta
# sudo -u postgres psql -c "create extension if not exists hstore_plpython3u schema public" aquameta
sudo -u postgres psql -c "create extension if not exists dblink schema public" aquameta
sudo -u postgres psql -c "create extension if not exists \"uuid-ossp\"" aquameta
sudo -u postgres psql -c "create extension if not exists pgcrypto schema public" aquameta
sudo -u postgres psql -c "create extension if not exists postgres_fdw" aquameta
# sudo -u postgres psql -c "create extension if not exists plv8" aquameta

# create aquameta core extensions
echo "Installing core Aquameta extensions..."
sudo -u postgres psql -c "create extension pg_catalog_get_defs schema pg_catalog" aquameta
sudo -u postgres psql -c "create extension meta" aquameta
sudo -u postgres psql -c "create extension bundle" aquameta
sudo -u postgres psql -c "create extension event" aquameta
sudo -u postgres psql -c "create extension endpoint" aquameta
sudo -u postgres psql -c "create extension widget" aquameta
sudo -u postgres psql -c "create extension semantics" aquameta
sudo -u postgres psql -c "create extension ide" aquameta
sudo -u postgres psql -c "create extension documentation" aquameta
# sudo -u postgres psql -f $SRC/src/sql/ide/000-ide.sql aquameta
# sudo -u postgres psql -f $SRC/src/pg-extension/documentation/000-datamodel.sql aquameta



#############################################################################
# install and checkout enabled bundles
#############################################################################
echo "Installing core bundles..."

echo "Please choose:"
echo "  a) Hub installl -- download bundles (and future updates)"
echo "     from the Aquameta bundle hub."
echo "  b) Offline install -- do not connect to the hub, install"
echo "     from source only."
REPLY=
while ! [[ $REPLY =~ ^[aAbB]$ ]]
do
	echo
	read -p "[A/b] " -n 1 -r
done

if [[ $REPLY =~ ^[bB]$ ]]
then
	if [ "$DEST" != "$SRC" ]; then
	    mkdir --parents $DEST
	    cp -R $SRC/bundles-available $DEST
	    cp -R $SRC/bundles-enabled $DEST
	fi

#	chown -R postgres:postgres $DEST/bundles-available
#	chown -R postgres:postgres $DEST/bundles-enabled

	echo "Loading bundles-enabled/*/*.csv ..."
	for D in `find $DEST/bundles-enabled/* \( -type l -o -type d \)`
	do
	    sudo -u postgres psql -c "select bundle.bundle_import_csv('$D')" aquameta
	done

	echo "Checking out head commit of every bundle ..."
	sudo -u postgres psql -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" aquameta
else
	for REMOTE in `find $SRC/src/remotes/*.sql -type f`
	do
	    sudo -u postgres psql aquameta -f $REMOTE
	done

	sudo -u postgres psql aquameta -c "select bundle.remote_mount(id) from bundle.remote_database"
	sudo -u postgres psql aquameta -c "select bundle.remote_pull_bundle(r.id, b.id) from bundle.remote_database r, hub.bundle b where b.name != 'org.aquameta.core.bundle'"
	echo "Checking out head commit of every bundle ..."
	sudo -u postgres psql aquameta -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;"
fi



#############################################################################
# grant default permissions for 'anonymous' and 'user' roles
#############################################################################

echo ""
echo "New User Registration Scheme"
echo "----------------------------"
echo "Please select a security scheme:"
echo "a) PRIVATE - No anonymous access, no anonymous user registration"
echo "b) OPEN REGISTRATION - Anonymous users may register for an account and read limited data"

REPLY=
until [[ $REPLY =~ ^[AaBb]$ ]]; do
	read -p "Choice? [a/B] " -n 1 -r
    echo
done

sudo -u postgres psql -f $SRC/src/privileges/000-general.sql aquameta

if [[ $REPLY =~ ^[Aa]$ ]]; then
	echo "Installing PRIVATE security scheme..."
	sudo -u postgres psql -f $SRC/src/privileges/001-anonymous.sql aquameta
else if [[ $REPLY =~ ^[Bb]$ ]]; then
        echo "Installing OPEN REGISTRATION scheme..."
        sudo -u postgres psql -f $SRC/src/privileges/001-anonymous-register.sql aquameta
    fi
fi

sudo -u postgres psql -f $SRC/src/privileges/002-user.sql aquameta



#############################################################################
# setup aquameta superuser
#############################################################################

echo "Superuser Registration"
echo "----------------------"
echo "Enter the name, email and password of the user you'd like to setup as superuser:"
read -p "Full Name: " NAME
read -p "Email Address: " EMAIL
read -p "PostgreSQL Username [$(logname)]: " ROLE
if [[ $ROLE = '' ]]
then
	ROLE=$(logname)
fi
read -s -p "Password: " PASSWORD

echo ""
echo "Creating superuser...."
REG_COMMAND="select endpoint.register_superuser('$EMAIL', '$PASSWORD', '$NAME', '$ROLE')"
sudo -u postgres psql -c "$REG_COMMAND" aquameta



#############################################################################
# finished!
#############################################################################
MACHINE_IP=`hostname --ip-address|cut -d ' ' -f1`
# EXTERNAL_IP=`dig +short myip.opendns.com @resolver1.opendns.com`
EXTERNAL_IP=`dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com`

echo ""
echo "Aquameta was successfully installed.  Next, login and configure your installation:"
echo ""
echo "Localhost link: http://localhost/login"
echo "Machine link:   http://$MACHINE_IP/login"
echo "External link:  http://$EXTERNAL_IP/login"

