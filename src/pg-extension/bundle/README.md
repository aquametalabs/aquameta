# bundle

Data version control system for PostgreSQL.

## Installation

### Requirements

Bundle requires the following extensions:

- [meta](https://github.com/aquametalabs/aquameta/tree/master/src/pg-extension/meta)
- uuid-ossp (included with PostgreSQL)
- pgcrypto (included with PostgreSQL)

```
create extension if not exists meta;
create extension if not exists pgcrypto schema public;
create extension if not exists "uuid-ossp" schema public;
```

### Install into PostgreSQL
```
cd bundle/
make && make install
```

### Create Extension
```
psql> CREATE EXTENSION bundle;
```

## API

### Bundles

#### `bundle_create( name text )`
#### `bundle_delete( bundle_id uuid )`

### Track Rows

#### `tracked_row_add( bundle_name text, row_id meta.row_id )`
#### `tracked_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )`

### Stage/Unstage Changes

#### `stage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )`
#### `stage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )`
#### `stage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )`
#### `stage_field_change( bundle_id uuid, field_id meta.field_id )`
#### `unstage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )`
#### `unstage_field_change( bundle_id uuid, field_id meta.field_id )`
#### `unstage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )`
#### `unstage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )`
#### `head_rows( bundle_name text )`

### Commit

#### `commit_log( bundle_name text )`
#### `commit( bundle_name text, commit_message text )`
#### `delete_commit( commit_id uuid )`

### Checkout

#### `checkout( bundle_id uuid )`

### Remotes
#### `diff_bundle_bundle_commits( bundle_table_a meta.relation_id, bundle_table_b relation_id meta.relation_id )`
#### `remote_clone( bundle_id uuid, source_schema_name text, dest_schema_name text)
#### `remote_mount( foreign_server_name text, schema_name text, host text, port integer, dbname text, username text, password text)

### Filesystem Import/Export
#### `bundle_export_csv( bundle_name text, directory text )`
#### `bundle_import_csv( bundle_name text, directory text )`
