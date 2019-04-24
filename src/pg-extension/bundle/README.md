# bundle

Data version control system for PostgreSQL.

## Bundles

A bundle is a version-controlled repository for a collection of rows.  Bundles have commits, each commit is a snapshot of a set of rows at a particular time.

```sql
bundle_create( name text )
bundle_delete( bundle_id uuid )
```

## Tracked Rows

Each bundles has a "scope of concern", which is the set of rows that it "tracks".  A new bundle doesn't track any rows.  Each row that the bundle tracks must be added to the bundle's scope of concern with the `tracked_row_add()` functions.

```sql
tracked_row_add( bundle_name text, row_id meta.row_id )
tracked_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
```

## Unracked Rows

Rows that are not tracked by any bundle (and not `ignored`) are considered "untracked"; the `untracked_row` view contains them.

## Ignored Rows, Relations and Schemas

Often times, not every row in the database will be under version control.  For example, if one were to install the bundle extension on an existing database, the `untracked_row` view would literally contain every row in the database, which in some scenarios would be much too slow.

As such, rows can be `ignored`, via the tables `ignored_schema`, `ignored_relation` and `ignored_row`.  A row in the `ignored_schema` table will ignore all rows in that schema, and `ignored_relation` will do the same.

## Stage/Unstage Changes

Once a row has been tracked, it can be "staged".  The stage is a virtual view of what will be saved to the version history on the next commit.  The contents of the stage can be viewed in the `bundle.stage_row` view.  It will contain the contents of the previous commit, plus any newly staged rows, minus any rows staged for deletion.

```sql
stage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
stage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
stage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )
stage_field_change( bundle_id uuid, field_id meta.field_id )
unstage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )
unstage_field_change( bundle_id uuid, field_id meta.field_id )
unstage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
unstage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
```

## Commit

Once staged changes are satisfactory, the user can issue a `bundle.commit()`, which will add the staged changes to the bundle's commit hsitory.  This commit history is stored inside the database, in the `bundle.commit` table, and sub-tables for containing the `rowset`, `rowset_row`s, and `rowset_row_field`s that are this bundle's contents.  

Though a bundle can have many commit's, only one commit can be the bundle's "head commit".  This commit is the one that the live database will be compared against for changes, and will be the parent of the next commit.  After a commit, the stage will be identical to the bundle's head, contained in `bundle.head_commit_row`, which can be viewed with the `head_rows()` function.

The bundle's commit history can be viewed with the `commit_log()` function.

```sql
commit_log( bundle_name text )
commit( bundle_name text, commit_message text )
delete_commit( commit_id uuid )
head_rows( bundle_name text )
```

## Checkout

Checking out a bundle will insert all the rows in the bundle's head_commit_id, into the live database.

```sql
checkout( bundle_id uuid )
```

## Remotes

Bundles can be pushed and pulled to and from other PostgreSQL databases.  Transfers occur through the `postgres_fdw` extension, which mounts the remote database's `bundle` schema in a local schema, whose name is configured by the `schema_name` argument of `remote_database_create()`.   Once a database has been "mounted", 

```sql
remote_database_create (foreign_server_name text, schema_name text, host text, port integer, dbname text, username text, password text)
remote_mount( remote_database_id )
remote_unmount( remote_database_id )
remote_is_mounted( remote_database_id )
diff_bundle_bundle_commits( bundle_table_a meta.relation_id, bundle_table_b relation_id meta.relation_id )
remote_pull_bundle( remote_database_id uuid, bundle_id uuid )
-- remote_push() -- coming soon
-- remote_pull() -- coming soon
```
## Filesystem Import/Export

Bundles can be imported and exported to and from the filesystem.

```sql
bundle_export_csv( bundle_name text, directory text )
bundle_import_csv( bundle_name text, directory text )
```
