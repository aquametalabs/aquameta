#!/bin/bash

mkdir -p /mnt/aquameta
./pgfs.py -d aquameta -u postgres /mnt/aquameta &
