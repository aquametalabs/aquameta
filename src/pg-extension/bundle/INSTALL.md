# Bundle Installation

## Requirements

Bundle requires the following extensions, which must be manually installed before bundle can be installed.

- [meta](https://github.com/aquametalabs/aquameta/tree/master/src/pg-extension/meta)
- uuid-ossp (included with PostgreSQL)
- pgcrypto (included with PostgreSQL)

```
create extension if not exists meta;
create extension if not exists pgcrypto schema public;
create extension if not exists "uuid-ossp" schema public;
```

## Install into PostgreSQL
```
cd bundle/
make && make install
```

### Create Extension
```
psql> CREATE EXTENSION bundle;
```
