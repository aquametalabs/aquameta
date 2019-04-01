
/*******************************************************************************
 * Bundle Utilities
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

-- export
-- saves bundle contents to filesystem.  overwrites if it is already there.
-- directory must already exist and be writable by postgres user.

create or replace function bundle.bundle_export_csv(bundle_name text, directory text)
 returns void
 language plpgsql
as $$
begin
    execute format('copy (select distinct * from bundle.bundle
        where name=''%s'') to ''%s/bundle.csv''', bundle_name, directory);

    execute format('copy (select distinct c.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        where b.name=%L) to ''%s/commit.csv''', bundle_name, directory);

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
        join bundle.blob on rrf.value_hash=blob.hash
        where b.name=%L order by blob.hash) to ''%s/blob.csv''', bundle_name, directory);
end
$$;


-- import
-- import a bundle from a csv export (created by above).

create or replace function bundle.bundle_import_csv(directory text)
 returns void
 language plpgsql
as $$
begin
    -- triggers must be disabled because bundle and commit have circilar
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
    execute format('create temporary table origin_temp(id uuid, name text, head_commit_id uuid) on commit drop');
    execute format('copy origin_temp from ''%s/bundle.csv''', directory);
    execute format('insert into bundle.bundle_origin_csv(directory, bundle_id) select %L, id from origin_temp', directory);
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
