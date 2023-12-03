/*******************************************************************************
 * Bundle Utilities
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

-- export
-- saves bundle contents to filesystem.  overwrites if it is already there.
-- directory must already exist and be writable by postgres user.

create or replace function bundle.bundle_export_csv(bundle_name text, directory text)
 returns void
 language plpgsql
as $$
begin
    -- check if bundle exists
    if not exists( select true from bundle.bundle b where b.name = bundle_name) then
        raise exception 'No such bundle with name %', bundle_name;
    end if;

    -- check that bundle has commits
    -- TODO: is this really a problem?
    if not exists( select true from bundle.bundle b join bundle.commit c on c.bundle_id = b.id where b.name = bundle_name) then
        raise exception 'No commits found in bundle %', bundle_name;
    end if;


    -- copy bundle contents to csv files
    -- checkout_commit_id is set to NULL explicitly, because it is only relevant to this current database
    execute format('copy (select b.id, b.name, b.head_commit_id, NULL /* checkout_commit_id */ from bundle.bundle b
        where b.name=''%s'' order by b.id) to ''%s/bundle.csv''', bundle_name, directory);

    execute format('copy (select distinct c.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        where b.name=%L order by c.id) to ''%s/commit.csv''', bundle_name, directory);

    execute format('copy (select distinct r.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        where b.name=%L order by r.id) to ''%s/rowset.csv''', bundle_name, directory);

    execute format('copy (select distinct rr.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        where b.name=%L order by rr.id) to ''%s/rowset_row.csv''', bundle_name, directory);

    execute format('copy (select distinct rrf.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id
        where b.name=%L order by rrf.id) to ''%s/rowset_row_field.csv''', bundle_name, directory);

    execute format('copy (select distinct blob.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id
        join bundle.rowset_row rr on rr.rowset_id=r.id
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id
        left join bundle.blob on rrf.value_hash=blob.hash
        where b.name=%L order by blob.hash) to ''%s/blob.csv''', bundle_name, directory);

    -- add a bundle_csv to track where this bundle was exported
    execute format('insert into bundle.bundle_csv(directory, bundle_id) select %L, id from bundle.bundle where name=%L', directory, bundle_name);
end
$$;


-- import
-- import a bundle from a csv export (created by above).

create or replace function bundle.bundle_import_csv(directory text, refresh_materialized_views boolean default true)
 returns uuid
 language plpgsql
as $$
declare
    bundle_id uuid;
    bundle_name text;
begin
    -- triggers must be disabled because bundle and commit have circular
    -- dependencies, and blob
    execute format('alter table bundle.bundle disable trigger all');
    execute format('alter table bundle.commit disable trigger all');
    execute format('copy bundle.bundle from ''%s/bundle.csv''', directory);
    execute format('copy bundle.commit from ''%s/commit.csv''', directory);

    -- copy the commit data
    execute format('copy bundle.rowset from ''%s/rowset.csv''', directory);
    execute format('copy bundle.rowset_row from ''%s/rowset_row.csv''', directory);
    execute format('copy bundle.blob from ''%s/blob.csv''', directory);
    execute format('copy bundle.rowset_row_field from ''%s/rowset_row_field.csv''', directory);
    execute format('alter table bundle.bundle enable trigger all');
    execute format('alter table bundle.commit enable trigger all');

    -- set the origin for this bundle
    execute format('create temporary table origin_temp(id uuid, name text, head_commit_id uuid, checkout_commit_id uuid) on commit drop');
    execute format('copy origin_temp from ''%s/bundle.csv''', directory);
    execute format('insert into bundle.bundle_csv(directory, bundle_id) select %L, id from origin_temp', directory);

    -- make sure that checkout_commit_is null
    -- FIXME: when you import multiple bundles in a transaction, this origin_temp table name collides...
    select name from origin_temp into bundle_name;
    update bundle.bundle set checkout_commit_id = NULL where name = bundle_name;

    -- refresh materialized views
    if refresh_materialized_views then
        execute format('refresh materialized view bundle.head_commit_row');
        execute format('refresh materialized view bundle.head_commit_field');
    end if;

    -- return bundle.id
    select id from origin_temp into bundle_id;
    return bundle_id;
end
$$;

-- garbage_collect()
-- deletes any blobs that are not referenced by any rowset_row_fields

create or replace function bundle.garbage_collect() returns void
as $$
    delete from bundle.blob where hash is null;
    delete from bundle.rowset_row_field where value_hash is null;
    delete from bundle.blob where hash not in (select value_hash from bundle.rowset_row_field);
    delete from bundle.rowset where id not in (select rowset_id from bundle.commit);
$$ language sql;




create type search_method as enum ('like','ilike','regex', 'iregex');
create type search_scope as enum ('head','stage','tracked','changed','history');

create or replace function bundle.search(
    term text,
    search_method search_method,
    scope search_scope,
    _bundle_id uuid default null)
returns table (
    bundle_id uuid,
    bundle_name text,
    commit_ids uuid[],

    row_schema_name text,
    row_relation_name text,
    row_pk_column_name text,
    row_pk_value text,
    field_name text,

    messages text[],
    value_hash text,
    value text
) as $$
declare
    search_stmt text;
begin
    search_stmt := 'select
        b.id as bundle_id,
        b.name,
        array_agg(c.id) as commit_ids,

        (rrf.field_id).schema_name as row_schema_name,
        (rrf.field_id).relation_name as row_relation_name,
        (rrf.field_id).pk_column_name as row_pk_column_name,
        (rrf.field_id).pk_value as row_pk_value,
        (rrf.field_id).column_name as field_name,

        array_agg(c.message),
        rrf.value_hash,
        value
        from bundle.bundle b
            join bundle.commit c on c.bundle_id=b.id ';
    case scope
        when 'head' then
        search_stmt := search_stmt || '
            join bundle.head_commit_row hcr on hcr.commit_id = c.id
            join bundle.head_commit_field rrf on rrf.row_id = hcr.row_id
            left join bundle.blob bb on rrf.value_hash = bb.hash ';
        when 'stage' then
        search_stmt := search_stmt || '
            join bundle.stage_row sr on sr.bundle_id = b.id
            join bundle.stage_row_field rrf on rrf.stage_row_id::text = sr.row_id::text '; --TODO: holy cown this cast to text speeds things up 70x
        when 'history' then
        search_stmt := search_stmt || '
            join bundle.rowset r on c.rowset_id=r.id
            join bundle.rowset_row rr on rr.rowset_id=r.id
            join bundle.rowset_row_field rrf on rrf.rowset_row_id = rr.id
            left join bundle.blob bb on rrf.value_hash = bb.hash ';
        else raise exception 'Not Yet Implemented';
    end case;

    case search_method
        when 'like' then
        search_stmt := search_stmt || ' where value like ''%%%s%%'' ';
        when 'ilike' then
        search_stmt := search_stmt || ' where value ilike ''%%%s%%'' ';
        when 'regex' then
        search_stmt := search_stmt || ' where value ~ ''%s'' ';
        when 'iregex' then
        search_stmt := search_stmt || ' where value ~* ''%s'' ';
    end case;

    if _bundle_id is not null then
         search_stmt := search_stmt || format(' and b.id=%L', _bundle_id);
    end if;

    search_stmt := search_stmt || '
        group by rrf.field_id, b.id, b.name, rrf.value_hash, value';

     -- TODO: escape single quotes
    search_stmt := format( search_stmt, term );
    raise notice 'search_stmt: %', search_stmt;
    return query execute search_stmt;
end;
$$ language plpgsql;
