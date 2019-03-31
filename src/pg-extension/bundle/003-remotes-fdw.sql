/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

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


-- bundle_commits_array( bundle_relation_id )
--
-- contains a row for each bundle in a database, containing the "commit" row of each commit in the bundle


create or replace function bundle_commits_array( bundle_relation_id meta.relation_id )
returns table (
    id uuid, name text, head_commit_id uuid, commits json
)
as $$
begin
    return query execute format('
        select
            b.id,
            b.name,
            b.head_commit_id,
            json_agg( json_build_object(
                ''id'', c.id,
                ''bundle_id'', c.bundle_id,
                ''message'', c.message,
                ''time'', c.time,
                ''parent_id'', c.parent_id
            )) as commits
        from %I.%I b
            join %I.commit c on c.bundle_id=b.id
        group by b.id, b.name, b.head_commit_id
    ',
        (bundle_relation_id::meta.schema_id).name,
        bundle_relation_id.name,
        (bundle_relation_id::meta.schema_id).name
    );
end;
$$ language plpgsql;


-- diff_bundle_bundle_commits( bundle_table_a, bundle_table_b )
--
-- outer-joins the bundle tables of databases, one row per bundle.  the row also contains a json aggregate of every commit in that bundle.

create or replace function diff_bundle_bundle_commits(
    bundle_table_a meta.relation_id,
    bundle_table_b meta.relation_id
) returns table (
    a_bundle_id uuid, a_name text, a_head_commit_id uuid, a_commits json,
    b_bundle_id uuid, b_name text, b_head_commit_id uuid, b_commits json
)
as $$
select
    a.id as a_bundle_id, a.name as a_name, a.head_commit_id as a_head_commit_id, a.commits as a_commits,
    b.id as b_bundle_id, b.name as b_name, b.head_commit_id as b_head_commit_id, b.commits as b_commits
    from bundle.bundle_commits_array( bundle_table_a ) a
        full outer join bundle.bundle_commits_array( bundle_table_b ) b
            on a.id = b.id
$$ language sql;


/*

EARLIER ATTEMPTS AT GREATNESS:



-- remote_bundle_level_diff ()
--
-- compare the bundles in two bundle schemas, typically a local one and a
-- remote one.  returns all bundles present in either database.

create or replace function remote_bundle_level_diff( local meta.relation_id, remote meta.relation_id )
returns table (
    local_id uuid, local_name text, local_head_commit_id uuid, local_commits_hash text[],
    remote_id uuid, remote_name text, remote_head_commit_id uuid, remote_commits_hash text[]
)
as $$
begin
    return query execute format('
        select
            local.id as local_id,
            local.name as local_name,
            local.head_commit_id as local_head_commit_id,
            array_agg(local_c.id::text) as local_commits_hash,
        from %I.%I local
            join %I.commit local_c


            remote.id as remote_id,
            remote.name as remote_name,
            remote.head_commit_id as remote_head_commit_id,
            array_agg(remote_c.id::text) as remote_commits_hash

        from %I.%I local
            full outer join %I.%I remote on remote.id = local.id
            left join %I.commit local_c on local_c.bundle_id=local.id
            left join %I.commit remote_c on remote_c.bundle_id=remote.id
        group by local_id, local_name, local_head_commit_id, remote_id, remote_name, remote_head_commit_id
        ',
        (local::meta.schema_id).name, local.name,
        (remote::meta.schema_id).name, remote.name,
        (local::meta.schema_id).name,
        (remote::meta.schema_id).name
    );
end;
$$
language plpgsql;

-- remote_commit_level_diff(bundle_name, schema1_name, schema2_name)
--
-- returns commits in remote but not local

create type commit_diff as (
    c1_id uuid,
    c1_bundle_id uuid,
    c1_message text,
    c1_time timestamp,
    c1_parent_id uuid,
    c1_role_id meta.role_id,

    c2_id uuid,
    c2_bundle_id uuid,
    c2_message text,
    c2_time timestamp,
    c2_parent_id uuid,
    c2_role_id meta.role_id
);

create or replace function remote_commit_level_diff (
    schema1_name text,
    schema2_name text
) returns setof commit_diff
as $$
begin
    return query execute format('
        select
            c1.id as c1_id,
            c1.bundle_id as c1_bundle_id,
            c1.message as c1_message,
            c1.time as c1_time,
            c1.parent_id as c1_parent_id,
            c1.role_id as c1_role_id,

            c2.id as c2_id,
            c2.bundle_id as c2_bundle_id,
            c2.message as c2_message,
            c2.time as c2_time,
            c2.parent_id as c2_parent_id,
            c2.role_id as c2_role_id

        from %I.commit c1
            full outer join %I.commit c2 on c1.id = c2.id and c1.bundle_id = c2.bundle_id
        where c1.id is null or c2.id is null',
        schema1_name,
        schema2_name
    );
end;
$$
language plpgsql;

*/

-- remote_clone ()
--
-- copy a repository from one bundle schema (typically a remote) to another (typically a local one)
create or replace function remote_clone( remote_database_id uuid, bundle_id uuid ) -- source_schema_name text, dest_schema_name text )
returns boolean as $$
declare
    source_schema_name text;
    dest_schema_name text;
begin
    select schema_name from bundle.remote_database where id = remote_database_id into source_schema_name;
    select 'bundle' into dest_schema_name;
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
    execute format ('insert into %2$I.bundle (id, name)
        select b.id, b.name from %1$I.bundle b
        where b.id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- commit
    execute format ('
        insert into %2$I.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    -- todo: ignored rows?

    execute format ('update %2$I.bundle
        set head_commit_id = (
            select b.head_commit_id
            from %1$I.bundle b
            where b.id=%3$L
    ) where id=%3$L', source_schema_name, dest_schema_name, bundle_id);

    execute format ('insert into bundle.bundle_origin_remote (bundle_id, remote_database_id) values( %L, %L )', bundle_id, remote_database_id);

    return true;
end;
$$
language plpgsql;
