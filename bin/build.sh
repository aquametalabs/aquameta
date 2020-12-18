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

