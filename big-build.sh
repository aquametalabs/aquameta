#!/bin/bash

set -euo pipefail

# make submods
cd scripts/
sudo ./make_install_extensions.sh
cd ..

# make endpoint
cd ../aq_endpoint
make
sudo make install
cd ../aquameta

# drop db
dropdb -f aquameta
createdb aquameta

# build go
go build

# start server
./aquameta -c conf/aquameta.toml 

