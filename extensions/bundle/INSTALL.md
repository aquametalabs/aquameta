# Bundle Installation

## Requirements

Bundle requires the following extensions:

- [meta](../meta)
- uuid-ossp (included with PostgreSQL)
- pgcrypto (included with PostgreSQL)

## Install into PostgreSQL
```bash
cd bundle/
make && make install
```


## Create Extensions
```sql
-- first install the meta extension
create extension if not exists hstore schema public;
create extension if not exists meta;

-- install bundle's dependencies
create extension if not exists pgcrypto schema public;
create extension if not exists "uuid-ossp" schema public;

-- install bundle
create extension bundle;
```
