# Bundle - Data version control system for PostgreSQL

This extension provides row-level snapshotted data version control for
PostgreSQL, similar to `git`.

## OVERVIEW

Here are the basic concepts.

BUNDLE NAME: Each bundle has a unique name, stored in the `bundle.name` column.
They follow the dot-notation naming convention
("com.flyingmonkeys.app.monkeyradar") (unless we think of a better idea, which
we might).

DATABASE SCOPE: Bundles do not version-control every row in the database; only
rows that have been explicitly "tracked" are in the scope of a particular
bundle's purvey.

COMMITS: Each bundle has a collection of "commits", snapshots of database rows
at a particular point in time.  Each commit asserts that at a particular time,
an explicit set of rows, identified by their `meta.row_id`, each had a set of
fields, identified by their `meta.field_id`, and that each field had a
particular value.

REPOSITORY:  Although commit history is stored in the database, these
historical snapshots do not exist in tables they originally existed in.
Instead they exist in a reified format, in bundle's internal commit history
tables, called they "repository".  They are not installed in the database until
they are "checked out".

WORKING COPY: When a bundle is "checked out", its rows are inserted into the
database in whatever schema and table the row's `meta.row_id` specifies.  This
checked-out version of a bundle is called the "working copy".  A bundle's
commit history typically never is modified, only added to.  New commits are
composed by changing the working copy of the database.  

ATOMIC CHANGE: In the bundle paradigm, only three things ever change in a
database:  Rows are created, rows are deleted, and fields are changed.  These
three atomic operations are the foundation of how bundle does version control.
As such, each commit is a collection of the above operations:  New rows can be
added to a new commit, old rows can be deleted, and the field value of rows can
be changed.

ANCESTRY: Every commit except for the very first one has a "parent", which
references the previous commit that this commit modified.  More than one commit
can share the same parent, for example if two people make modifications to a
bundle at the same time.  Commits can also "merge" two previous commits
together, as long as those commits share a common ancestor.  Thus the structure
of the commit history of a bundle is directed acyclic graph (DAG).

SCHEMA CHANGE: Bundles can also track schema changes.  It does so by building
on the foundation of the [meta](../meta) extension, which represents the
database schema as data.  As such, a schema change in bundle, say a column
deletion, is just another row delete, however this row is from the
`meta.column` table.

HEAD: When a commit is checked out, the working copy at that time is identical
to the contents of the checked-out commit.  This commit is flagged at checkout
as the "head commit", the commit that the working copy is compared with.  When
a new commit is made, this head commit will be the new commit's parent.

OFFSTAGE_CHANGES: As the working copy is changed, it diverges from the head
commit.  These changes can be viewed in the views `offstage_row_added`,
`offstage_row_deleted` and `offstage_field_changed`.  Together, these show
every place that the working copy is different from the head commit.

STAGING: When a particular data change is deemed suitable for inclusion in the
next commit, it needs to be "staged".  The stage contains the set of changes
that will be included in the next commit, and any change to the working copy
that is not staged before commit will not be included.  Staged changes,
similarly to offstage changes, are stored in the tables `stage_row_added`,
`stage_row_deleted` and `stage_field_changed`.

COMMITTING: Committing creates a new snapshot of the bundle's rows.  It is the
same as the previous head commit, except for any new changes that have been
staged.  Unstaged changes are not included.  When making a new commit, the
commiter includes a description of the changes in the commit, and their author.

MERGING: Often times, two developers work in parallel on the same bundle,
making changes off of the same head commit.  When this happens, the two
developers' commits share the same parent, and the commit history forks.  These
forks might just be a single commit, or a long chain of parallel commits.  It
is often desirable to "merge" these two forks back together, so that a single
commit contains both developers' work.  A merge applies the changes of another
"merge commit" to the head commit.  Any field that only one developer changed
since departure from their common commit ancestor is said to be
non-conflicting, but any field change on both branches is said to be
conflicting.  Non-conflicting changes are applied to the working copy and
staged, but conflicting changes are only applied to the working copy and not
staged.  That way the merger may examine the conflicting changes and choose the
best or combine them.

PUSH: Commits can be sent from one database to another.  This is called a push.

PULL: Commits can be downloaded from another database.  This is called a pull.

These are the basic concepts.  Together, they allow basic version control of
the database.

## USAGE

### Creating a new bundle

```sql
bundle_create( name text )
bundle_delete( bundle_id uuid )
```

### Tracked Rows

Each bundles has a "scope of concern", which is the set of rows that it
"tracks".  A new bundle doesn't track any rows.  Each row that the bundle
tracks must be added to the bundle's scope of concern with the
`tracked_row_add()` functions.

```sql
tracked_row_add( bundle_name text, row_id meta.row_id )
tracked_row_add( bundle_name text, schema_name text, relation_name text, pk_column_name text, pk_value text )
```

### Unracked Rows

Rows that are not tracked by any bundle (and not `ignored`) are considered
"untracked"; the `untracked_row` view contains them.

### Ignored Rows, Relations and Schemas

Often times, not every row in the database will be under version control.  For
example, if one were to install the bundle extension on an existing database,
the `untracked_row` view would literally contain every row in the database,
which in some scenarios would be much too slow.

As such, rows can be `ignored`, via the tables `ignored_schema`,
`ignored_relation` and `ignored_row`.  A row in the `ignored_schema` table will
ignore all rows in that schema, and `ignored_relation` will do the same.

### Stage/Unstage Changes

Once a row has been tracked, it can be "staged".  The stage is a virtual view
of what will be saved to the version history on the next commit.  The contents
of the stage can be viewed in the `bundle.stage_row` view.  It will contain the
contents of the previous commit, plus any newly staged rows, minus any rows
staged for deletion.

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

### Commit

Once staged changes are satisfactory, the user can issue a `bundle.commit()`,
which will add the staged changes to the bundle's commit hsitory.  This commit
history is stored inside the database, in the `bundle.commit` table, and
sub-tables for containing the `rowset`, `rowset_row`s, and `rowset_row_field`s
that are this bundle's contents.  

Though a bundle can have many commit's, only one commit can be the bundle's
"head commit".  This commit is the one that the live database will be compared
against for changes, and will be the parent of the next commit.  After a
commit, the stage will be identical to the bundle's head, contained in
`bundle.head_commit_row`, which can be viewed with the `head_rows()` function.

The bundle's commit history can be viewed with the `commit_log()` function.

```sql
commit_log( bundle_name text )
commit( bundle_name text, commit_message text )
delete_commit( commit_id uuid )
head_rows( bundle_name text )
```

### Checkout

Checking out a bundle will insert all the rows in the bundle's head_commit_id,
into the live database.

```sql
checkout( bundle_id uuid )
```

### Remotes

Bundles can be pushed and pulled to and from other PostgreSQL databases.
Transfers occur through the `postgres_fdw` extension, which mounts the remote
database's `bundle` schema in a local schema, whose name is configured by the
`schema_name` argument of `remote_database_create()`.   Once a database has
been "mounted", 

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
### Filesystem Import/Export

Bundles can be imported and exported to and from the filesystem.

```sql
bundle_export_csv( bundle_name text, directory text )
bundle_import_csv( bundle_name text, directory text )
```
