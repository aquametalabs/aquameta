/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path=bundle;

/*******************************************************************************
*
*
* BUNDLE REMOTES -- postgres_fdw
*
* This version uses the postgres_fdw foreign data wrapper to mount remote
* databases via a normal postgresql connection.  It uses IMPORT FOREIGN SCHEMA
* to import the bundle schema, and then provides various comparison functions
* for push, pull and merge.
* 
*******************************************************************************/
create extension postgres_fdw schema public;


-- here's a table where you can stash some saved connections.
create table remote_database (
    id uuid default public.uuid_generate_v4() not null,
    foreign_server_name text,
    schema_name text,
    host text,
    port integer,
    dbname text,
    username text,
    password text
);


-- remote_mount()
--
-- setup a foreign server to a remote, and import it's bundle schema

create or replace function remote_mount (
    foreign_server_name text,
    schema_name text,
    host text,
	port integer,
    dbname text,
    username text,
    password text
)
returns boolean as
$$
begin
    execute format(
        'create server %I
            foreign data wrapper postgres_fdw
            options (host %L, port %L, dbname %L)',

        foreign_server_name, host, port, dbname
    );


    execute format(
        'create user mapping for public server %I options (user %L, password %L)',
        foreign_server_name, username, password
    );

    execute format(
        'create schema %I',
        schema_name
    );

    execute format(
        'import foreign schema bundle from server %I into %I options (import_default %L)',
        foreign_server_name, schema_name, 'true'
    );

    return true;
end;
$$ language plpgsql;




-- remote_diff ()
--
-- compare the bundles in two bundle schemas, typically a local one and a
-- remote one.  returns bundles present in the local but not the remote,
-- or visa versa.

create or replace function remote_bundle_existence_diff( local meta.relation_id, remote meta.relation_id )
returns table (
    local_id uuid, local_name text, local_head_commit_id uuid,
    remote_id uuid, remote_name text, remote_head_commit_id uuid
)
as $$
begin
    raise log 'local: %s', local::text;
    return query execute format('
        select
            local.id as local_id, local.name as local_name, local.head_commit_id as local_head_commit_id,
            remote.id as remote_id, remote.name as remote_name, remote.head_commit_id as remote_head_commit_id
        from %I.%I local
            full outer join %I.%I remote
                using (id, name)
        ',
        (local::meta.schema_id).name, local.name,
        (remote::meta.schema_id).name, remote.name
    );
end;
$$
language plpgsql;

-- remote_diff_commits (schema1_name, schema2_name)
--
-- returns commits in schema1 but not in schema2, or visa versa

/*
we gonna deprecate this?

create or replace function remote_diff_commits( local meta.relation_id, remote meta.relation_id )
returns table(
    local_id uuid, local_bundle_id uuid, local_role_id meta.role_id, local_parent_id uuid, local_time timestamp, local_message text,
    remote_id uuid, remote_bundle_id uuid, remote_role_id meta.role_id, remote_parent_id uuid, remote_time timestamp, remote_message text
)
as $$
begin
    return query execute format('
        select
            local.id as local_id, local.bundle_id as bundle_id, local.role_id as local_role_id, local.parent_id as local_parent_id, local.time as local_time, local.message as local_message,
            remote.id as remote_id, remote.bundle_id as bundle_id, remote.role_id as remote_role_id, remote.parent_id as remote_parent_id, remote.time as remote_time, remote.message as remote_message
        from %I.%I local
        full outer join %I.%I remote on local.id = remote.id
        where local.id is null or remote.id is null
        ',
        (local::meta.schema_id).name, local.name,
        (remote::meta.schema_id).name, remote.name
    );
end;
$$
language plpgsql;
*/

create type commit_diff as (
    c1_id uuid,
    c1_message text,
    c1_time timestamp,
    c1_parent_id uuid,
    c1_role_id meta.role_id,
    c2_id uuid,
    c2_message text,
    c2_time timestamp,
    c2_parent_id uuid,
    c2_role_id meta.role_id
);

-- remote_commits_existence_diff(bundle_name, schema1_name, schema2_name)
--
-- returns commits in remote but not local

create or replace function remote_commits_existence_diff (
    bundle_name text,
    schema1_name text,
    schema2_name text
) returns setof commit_diff
as $$
begin
    return query execute format('
        select
            c1.id as c1_id,
            c1.message as c1_message,
            c1.time as c1_time,
            c1.parent_id as c1_parent_id,
            c1.role_id as c1_role_id,

            c2.id as c2_id,
            c2.message as c2_message,
            c2.time as c2_time,
            c2.parent_id as c2_parent_id,
            c2.role_id as c2_role_id

        from %I.bundle b
            join %I.commit c1 on c1.bundle_id = b.id
            full outer join %I.commit c2 on c2.id = c1.id
        where b.name=%L
        and (c1.id is null or c2.id is null)',
        schema1_name,
        schema1_name,
        schema2_name,
        bundle_name
    );
end;
$$
language plpgsql;

-- remote_clone ()
--
-- copy a repository from one bundle schema (typically a remote) to another (typically a local one)

create or replace function remote_clone( bundle_id uuid, source_schema_name text, dest_schema_name text )
returns boolean as $$
begin
    -- rowset
    execute format ('insert into %2$I.rowset 
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row
    execute format ('
        insert into %2$I.rowset_row 
        select rr.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- blob
    execute format ('
        insert into %2$I.blob
        select b.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
            join %1$I.blob b on f.value_hash = b.hash
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row_field
    execute format ('
        insert into %2$I.rowset_row_field 
        select f.* from %1$I.commit c 
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- bundle
    execute format ('insert into %2$I.bundle
		(id, name)
        select b.id, b.name from %1$I.bundle b
        where b.id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- commit
    execute format ('
        insert into %2$I.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

	execute format ('update %2$I.bundle
		set head_commit_id = (
        select b.head_commit_id
		from %1$I.bundle b
        where b.id=%3$L) where id=%3$L', source_schema_name, dest_schema_name, bundle_id);


    return true;
end;
$$
language plpgsql;

commit;
