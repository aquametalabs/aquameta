/*******************************************************************************
 * Bundle Remotes
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/*******************************************************************************
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


create or replace function bundle.remote_mount (
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
            options (host %L, port %L, dbname %L, fetch_size ''1000'', extensions %L)',

        foreign_server_name, host, port, dbname, 'uuid-ossp'
    );

    execute format(
        'create user mapping for public server %I options (user %L, password %L)',
        foreign_server_name, username, password
    );

    execute format(
        'create schema %I',
        schema_name
    );

    execute format('
        import foreign schema bundle limit to
            (bundle, commit, rowset, rowset_row, rowset_row_field, blob, _bundle_blob)
        from server %I into %I options (import_default %L)',
        foreign_server_name, schema_name, 'true'
    );

    return true;
end;
$$ language plpgsql;



create or replace function bundle.remote_mount( remote_database_id uuid ) returns boolean as $$
begin
    execute format ('select bundle.remote_mount(
        foreign_server_name,
        schema_name,
        host,
        port,
        dbname,
        username,
        password)
    from bundle.remote_database
    where id = %L', remote_database_id);
    return true;
exception
    when others then return false;
end;

$$ language plpgsql;



create or replace function bundle.remote_unmount( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
begin
    select schema_name, foreign_server_name from bundle.remote_database where id = remote_database_id into _schema_name, _foreign_server_name;
    execute format('drop schema if exists %I cascade', _schema_name);
    execute format('drop server if exists %I cascade', _foreign_server_name);
    return true;
end;
$$ language plpgsql;



create or replace function bundle.remote_is_mounted( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
    has_schema boolean;
    has_server boolean;
    has_tables boolean;
begin
    select schema_name, foreign_server_name from bundle.remote_database where id = remote_database_id into _schema_name, _foreign_server_name;
    execute format ('select (count(*) = 1) from meta.schema where name = %L', _schema_name) into has_schema;
    execute format ('select (count(*) = 1) from meta.foreign_server where name = %L', _foreign_server_name) into has_server;
    execute format ('select (count(*) = 7) from meta.foreign_table where schema_name = %L and name in (''bundle'',''commit'',''rowset'',''rowset_row'',''rowset_row_field'',''blob'',''_bundle_blob'')', _schema_name) into has_tables;
    return has_schema and has_server and has_tables;
end;
$$ language plpgsql;



create or replace function bundle.remote_is_online( remote_database_id uuid ) returns boolean as $$
declare
    _schema_name text;
    _foreign_server_name text;
    is_online boolean;
begin
    select schema_name, foreign_server_name from bundle.remote_database where id = remote_database_id into _schema_name, _foreign_server_name;

    -- xocolatl | you could do something like  create foreign table pg_temp.test(i int) server s options (table '(select 1)'); 
    execute format ('select count(*) from %I.bundle where name = ''connection_test''', _schema_name);
    return true;
exception
    when others then
        return false;
end
$$ language plpgsql;



-- bundle_commits_array( bundle_relation_id )
--
-- contains a row for each bundle in a database, containing the "commit" row of each commit in the bundle

create or replace function bundle.bundle_commits_array( bundle_relation_id meta.relation_id, bundle_id uuid default null )
returns table (
    id uuid, name text, head_commit_id uuid, commits json
)
as $$
declare 
    bundle_filter_stmt text;
begin
    bundle_filter_stmt := '';
    if bundle_id is not null then
        bundle_filter_stmt := format('where bundle_id = %L', bundle_id);
    end if;
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
        %s
        group by b.id, b.name, b.head_commit_id
    ',
        (bundle_relation_id::meta.schema_id).name,
        bundle_relation_id.name,
        (bundle_relation_id::meta.schema_id).name,
        bundle_filter_stmt
    );
end;
$$ language plpgsql;



-- diff_bundle_bundle_commits( bundle_table_a, bundle_table_b )
--
-- outer-joins the bundle tables of databases, one row per bundle.  the row also contains a json aggregate of every commit in that bundle.

create or replace function bundle.remote_commits_diff(
    remote_database_id uuid,
    bundle_id uuid default null
) returns table (
    a_bundle_id uuid, a_name text, a_head_commit_id uuid, a_commits json,
    b_bundle_id uuid, b_name text, b_head_commit_id uuid, b_commits json
)
as $$
declare
    bundle_filter_stmt text;
    remote_schema_name text;
    remote_host text;
begin
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_host;

    return query execute format('
        select a.id as a_bundle_id, a.name as a_name, a.head_commit_id as a_head_commit_id, a.commits as a_commits,
            b.id as b_bundle_id, b.name as b_name, b.head_commit_id as b_head_commit_id, b.commits as b_commits
        from bundle.bundle_commits_array( meta.relation_id(''bundle'',''bundle''), %L ) a
            full outer join bundle.bundle_commits_array( meta.relation_id (%L,''bundle''), %L) b
                on a.id = b.id
        ', bundle_id, remote_schema_name, bundle_id );
end;
$$ language plpgsql;


/*

create or replace function bundle.remote_commits_ahead( remote_database_id uuid, bundle_id uuid) 
returns bundle.commit
as $$
declare
    source_schema_name text;
    source_host text;
    source_bundle_name text;
    source_bundle_id uuid;
begin
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_host;
    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;
    raise notice 'Cloning bundle % (%) from %...', source_bundle_name, source_bundle_id, source_host;

    execute format ('select c.* from %1$I.bundle b join %1$I.commit c on c.bundle_id = b.id where b.id = %2$L and c.id not in (select c.id from bundle.commit c)',
        remote

$$ language sql;
*/



-- remote_pull_bundle()
--
-- copy a repository from one bundle schema (typically a remote) to another (typically a local one)
create or replace function bundle.remote_pull_bundle( remote_database_id uuid, bundle_id uuid ) -- source_schema_name text, dest_schema_name text )
returns boolean as $$
declare
    source_schema_name text;
    source_host text;
    dest_schema_name text;
    source_bundle_name text;
    source_bundle_id uuid;
begin
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_host;

    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;
    raise notice 'Cloning bundle % (%) from %...', source_bundle_name, source_bundle_id, source_host;

    --------------- transfer --------------
    -- rowset
    raise notice '...rowset';
    execute format ('insert into bundle.rowset
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into bundle.rowset_row
        select rr.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- blob
    raise notice '...blob';
    execute format ('
        insert into bundle.blob
        select bb.hash, bb.value from %1$I._bundle_blob bb
        where bb.bundle_id=%2$L', source_schema_name, bundle_id);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into bundle.rowset_row_field
        select f.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- bundle
    raise notice '...bundle';
    execute format ('insert into bundle.bundle (id, name)
        select b.id, b.name from %1$I.bundle b
        where b.id=%2$L', source_schema_name, bundle_id);

    -- commit
    raise notice '...commit';
    execute format ('
        insert into bundle.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%2$L', source_schema_name, bundle_id);

    -- bundle.head_commit_id
    -- TODO: audit this in light of checkout_commit_id
    execute format ('update bundle.bundle
        set head_commit_id = (
            select b.head_commit_id
            from %1$I.bundle b
            where b.id=%2$L
    ) where id=%2$L', source_schema_name, bundle_id);

    execute format ('insert into bundle.bundle_origin_remote (bundle_id, remote_database_id) values( %L, %L )', bundle_id, remote_database_id);

    return true;
end;
$$
language plpgsql;



create or replace function bundle.remote_push_bundle( remote_database_id uuid, bundle_id uuid ) -- source_schema_name text, dest_schema_name text )
returns boolean as $$
declare
    remote_schema_name text;
    remote_host text;
    source_bundle_name text;
begin
    
    -- these used to be arguments, but now they're not.  we need to track remote_database_id explicitly.
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_host;

    select name from bundle.bundle where id = bundle_id
    into source_bundle_name;

    raise notice 'Pushing bundle % (%) from %...', source_bundle_name, bundle_id, remote_host;
    raise notice '...bundle';
    execute format ('insert into %1$I.bundle (id,name)
        select b.id, b.name from bundle.bundle b
        where b.id=%2$L', remote_schema_name, bundle_id);

    perform bundle.remote_push_commits( remote_database_id, bundle_id );

    raise notice '...updating bundle.head_commit_id';
    execute format ('update bundle.bundle b
        set head_commit_id=(select head_commit_id from %1$I.bundle b where b.id=%2$L)
        where b.id=%2$L', remote_schema_name, bundle_id);
    return true;
end;
$$
language plpgsql;



/*
 * bundle.remote_pull_commits
 *
 * transfer from remote all the commits that are not in the local repostiory for specified bundle
 *
 */

create or replace function bundle.remote_pull_commits( remote_database_id uuid, bundle_id uuid )
returns boolean as $$
declare
	dest_schema_name text;
	source_host text;
	source_schema_name text;
	source_bundle_name text;
	source_bundle_id uuid;
	new_commit_ids text;
    new_commits_count integer;
    rowset_count integer;
begin
    -- these used to be arguments, but now they're not.  we need to track remote_database_id explicitly.
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into source_schema_name, source_host;

    -- dest_schema_name
    select 'bundle' into dest_schema_name;

    -- source
    execute format ('select b.name, b.id from %1$I.bundle b where id=%2$L', source_schema_name, bundle_id) into source_bundle_name, source_bundle_id;

    -- new_commit_ids - commits in the bundle
    execute format ('
        select count(*), string_agg(quote_literal(c.id::text),'','')
            from %1$I.commit c
            join %1$I.bundle b on c.bundle_id = b.id
            where b.id = %2$L
                and c.id not in (select id from bundle.commit where bundle_id = %2$L)
        ', source_schema_name, bundle_id)
        into new_commits_count, new_commit_ids;

        if new_commits_count = 0 then 
            new_commit_ids = quote_literal(false);
        end if;

    -- notice
    raise notice 'Pulling % new commits for % (%) from %...', 
        new_commits_count, source_bundle_name, source_bundle_id, source_host;

    -- raise notice 'new_commit_ids: %', new_commit_ids;

    -- rowset
    raise notice '...rowset';
    execute format ('insert into %2$I.rowset
        select r.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)',
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into %2$I.rowset_row
        select rr.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)',
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- blob TODO: stop transferring all the blobs for just a pull
    raise notice '...blob';
    execute format ('
        insert into %2$I.blob
        select bb.hash, bb.value
            from %1$I._bundle_blob bb
            where bb.bundle_id=%3$L',
        source_schema_name, dest_schema_name, bundle_id);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into %2$I.rowset_row_field
        select f.* from %1$I.commit c
            join %1$I.rowset r on c.rowset_id = r.id
            join %1$I.rowset_row rr on rr.rowset_id = r.id
            join %1$I.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%3$L
            and c.id in (%4$s)', 
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    -- commit
    raise notice '...commit';
    execute format ('insert into %2$I.commit
        select c.* from %1$I.commit c
        where c.bundle_id=%3$L
            and c.id in (%4$s)
        order by c.time asc', -- TODO: we're just sorting by time here which is a hack.  build the parent_id tree recursively.
        source_schema_name, dest_schema_name, bundle_id, new_commit_ids);

    return true;

end;
$$ language plpgsql;



/*
 * bundle.remote_push_commits()
 *
 * transfer from remote all the commits that are not in the local repostiory for specified bundle
 *
 */

create or replace function bundle.remote_push_commits( remote_database_id uuid, bundle_id uuid )
returns boolean as $$
declare
	dest_schema_name text;
	remote_host text;
	remote_schema_name text;
	remote_bundle_name text;
	remote_bundle_id uuid;
	new_commit_ids text;
    new_commits_count integer;
    rowset_count integer;
begin
    -- remote_schema_name, remote_host
    select schema_name, host from bundle.remote_database
        where id = remote_database_id
	into remote_schema_name, remote_host;

    -- dest_schema_name
    select 'bundle' into dest_schema_name;

    -- remote
    execute format ('select b.name, b.id from bundle.bundle b where id=%1$L', bundle_id) into remote_bundle_name, remote_bundle_id;

    -- new_commit_ids - commits in the bundle
    execute format ('
        select count(*), string_agg(quote_literal(c.id::text),'','')
            from bundle.commit c
            join bundle.bundle b on c.bundle_id = b.id
            where b.id = %2$L
                and c.id not in (select id from %1$I.commit where bundle_id = %2$L)
            group by c.time
            order by c.time asc
        ', remote_schema_name, bundle_id)
        into new_commits_count, new_commit_ids;

        if new_commits_count = 0 then 
            new_commit_ids = quote_literal(false);
        end if;


    -- notice
    raise notice 'Pushing % new commits for % (%) from %...', 
        new_commits_count, remote_bundle_name, remote_bundle_id, remote_host;

    -- raise notice 'new_commit_ids: %', new_commit_ids;

    -- rowset
    raise notice '...rowset';
    execute format ('insert into %1$I.rowset
        select r.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)',
        remote_schema_name, bundle_id, new_commit_ids);

    -- rowset_row
    raise notice '...rowset_row';
    execute format ('
        insert into %1$I.rowset_row
        select rr.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)',
        remote_schema_name, bundle_id, new_commit_ids);

    -- blob TODO: stop transferring all the blobs for just a pull
    raise notice '...blob';
    execute format ('
        insert into %1$I.blob
        select distinct bb.hash, bb.value from bundle.bundle b
            join bundle.commit c on c.bundle_id = b.id
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
            join bundle.blob bb on rrf.value_hash = bb.hash
        where b.id=%2$L
            and c.id in (%3$s)',
            -- and bb.hash not in (select all the hashes that aren't new.... optimization)
        remote_schema_name, bundle_id, new_commit_ids);

    -- rowset_row_field
    raise notice '...rowset_row_field';
    execute format ('
        insert into %1$I.rowset_row_field
        select f.* from bundle.commit c
            join bundle.rowset r on c.rowset_id = r.id
            join bundle.rowset_row rr on rr.rowset_id = r.id
            join bundle.rowset_row_field f on f.rowset_row_id = rr.id
        where c.bundle_id=%2$L
            and c.id in (%3$s)', 
        remote_schema_name, bundle_id, new_commit_ids);

    -- commit
    raise notice '...commit';
    execute format ('insert into %1$I.commit
        select c.* from bundle.commit c
        where c.bundle_id=%2$L
            and c.id in (%3$s)
        order by c.time asc', -- TODO: we're just sorting by time here which is a hack.  build the parent_id tree recursively.
        remote_schema_name, bundle_id, new_commit_ids);

    return true;
end;
$$ language plpgsql;



/* optimization view for postgres_fdw */

create or replace view _bundle_blob as
select distinct on (b.id, bb.hash) b.id as bundle_id, bb.* from bundle.bundle b
    join bundle.commit c on c.bundle_id = b.id
    join bundle.rowset r on c.rowset_id = r.id
    join bundle.rowset_row rr on rr.rowset_id = r.id
    join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
    join bundle.blob bb on bb.hash = rrf.value_hash;
