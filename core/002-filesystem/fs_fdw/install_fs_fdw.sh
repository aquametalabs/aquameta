#!/bin/bash
psql -c 'create extension multicorn' aquameta
pip install .
cat fs_fdw.sql | psql -U postgres aquameta
