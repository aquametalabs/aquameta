#!/bin/bash
# set working directory and destination directory
SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# install extensions into PostgreSQL's extensions/ directory
echo "Building core PostgreSQL extensions..."
cd $SRC/../extensions/pg_catalog_get_defs && make && make install
cd $SRC/../extensions/meta && make && make install
cd $SRC/../extensions/bundle && make && make install
cd $SRC/../extensions/event && make && make install

# build the plgo part of extension
# (disabled because for now we're just not using templates)
# cd $SRC/src/pg-extension/endpoint/endpoint && /home/eric/go/bin/plgo . && \
#     cp build/endpoint.so .. && \
#     cp build/endpoint.h .. && \
#     cp build/endpoint--0.1.sql ../003-plgo.sql
# cd $SRC/extensions/endpoint && make with_llvm=no

# deprecated
# cd $SRC/../extensions/email && make && make install

cd $SRC/../extensions/endpoint && make && make install
cd $SRC/../extensions/widget && make && make install
cd $SRC/../extensions/semantics && make && make install
cd $SRC/../extensions/documentation && make && make install
cd $SRC/../extensions/ide && make && make install

