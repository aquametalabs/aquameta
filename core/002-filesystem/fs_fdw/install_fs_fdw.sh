#!/bin/bash
echo 'create extension multicorn' | psql -U postgres aquameta
pip install .
cat fs_fdw.sql | psql -U postgres aquameta
