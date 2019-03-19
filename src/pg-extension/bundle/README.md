# bundle

Data version control system for PostgreSQL.

## Bundles

A bundle is a version-controlled repository for a collection of rows.  Bundles have commits, each commit is a snapshot of a set of rows at a particular time.

### bundle_create( name text )
### bundle_delete( bundle_id uuid )

## Tracked Rows

Each bundles has a "scope of concern", which is the set of rows that it "tracks".  A new bundle doesn't track any rows.  Each row that the bundle tracks must be added to the bundle's scope of concern with the `tracked_row_add()` functions.

### tracked_row_add( bundle_name text, row_id meta.row_id )
### tracked_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )

## Stage/Unstage Changes

Once a row has been tracked, it can be "staged".  The stage is a virtual view of what will be saved to the version history on the next commit.  The contents of the stage can be viewed in the `bundle.stage_row` view.

### stage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
### stage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
### stage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )
### stage_field_change( bundle_id uuid, field_id meta.field_id )
### unstage_field_change( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text, column_name )
### unstage_field_change( bundle_id uuid, field_id meta.field_id )
### unstage_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
### unstage_row_delete( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )

## Commit

Once staged changes are satisfactory, the user can issue a `bundle.commit()`, which will add the staged changes to the bundle's commit hsitory.  This commit history is stored inside the database, in the `bundle.commit` table, and sub-tables for containing the `rowset`, `rowset_row`s, and `rowset_row_field`s that are this bundle's contents.  

Though a bundle can have many commit's, only one commit can be the bundle's "head commit".  This commit is the one that the live database will be compared against for changes, and will be the parent of the next commit.  After a commit, the stage will be identical to the bundle's head, contained in `bundle.head_commit_row`, which can be viewed with the `head_rows()` function.

The bundle's commit history can be viewed with the `commit_log()` function.

### commit_log( bundle_name text )
### commit( bundle_name text, commit_message text )
### delete_commit( commit_id uuid )
### head_rows( bundle_name text )

## Checkout

Checking out a bundle will create all the rows currently in the bundle, in the live database.  Only the head commit of a bundle can be checked out.

### checkout( bundle_id uuid )

## Remotes

Bundles can be pushed and pulled to and from other PostgreSQL databases.

### diff_bundle_bundle_commits( bundle_table_a meta.relation_id, bundle_table_b relation_id meta.relation_id )
### remote_clone( bundle_id uuid, source_schema_name text, dest_schema_name text)
### remote_mount( foreign_server_name text, schema_name text, host text, port integer, dbname text, username text, password text)

## Filesystem Import/Export

Bundles can be imported and exported to and from the filesystem.

### bundle_export_csv( bundle_name text, directory text )
### bundle_import_csv( bundle_name text, directory text )
