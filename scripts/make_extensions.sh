#!/bin/bash
# exit on failure
set -e
set -o pipefail

echo "path: $PATH"

#############################################################################
#
# Aquameta Extension Builder
# Makes each extension with `make`, optionally installs them with `make install`.
#
#############################################################################

echo "                                           __          "
echo "_____    ________ _______    _____   _____/  |______   "
echo "\__  \  / ____/  |  \__  \  /     \_/ __ \   __\__  \  "
echo " / __ \< <_|  |  |  // __ \|  Y Y  \  ___/|  |  / __ \_"
echo "(____  /\__   |____/(____  /__|_|  /\___  >__| (____  /"
echo "     \/    |__|          \/      \/     \/          \/ "
echo "        [ version 0.3.0 - extensions builder ]"
echo ""
echo ""

# set working directory and destination directory
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#############################################################################
# prompt for $DEST location
#############################################################################
# read -p "Installation directory [$SRC]: " DEST
# DEST=${DEST:-$SRC}

#############################################################################
# aquameta postgresql extensions
#############################################################################

# install extensions into PostgreSQL's extensions/ directory
echo "Building core PostgreSQL extensions..."
cd $SRC/../extensions/pg_catalog_get_defs && make
cd $SRC/../extensions/meta && make
cd $SRC/../extensions/bundle && make
cd $SRC/../extensions/event && make

# build the plgo part of extension
# (disabled because for now we're just not using templates)
# cd $SRC/src/pg-extension/endpoint/endpoint && /home/eric/go/bin/plgo . && \
#     cp build/endpoint.so .. && \
#     cp build/endpoint.h .. && \
#     cp build/endpoint--0.1.sql ../003-plgo.sql
# cd $SRC/extensions/endpoint && make with_llvm=no

cd $SRC/../extensions/endpoint && make
cd $SRC/../extensions/widget && make
cd $SRC/../extensions/semantics && make
cd $SRC/../extensions/documentation && make
cd $SRC/../extensions/ide && make

