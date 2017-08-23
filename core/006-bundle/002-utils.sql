
/*******************************************************************************
 * Bundle Remotes
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

set search_path=bundle;

-- bundle import and export functions

create or replace function bundle.bundle_export_csv(bundle_name text, directory text)
 returns void
 language plpgsql
as $$
begin
    execute format('copy (select * from bundle.bundle
        where name=''%s'') to ''%s/bundle.csv''', bundle_name, directory);
    execute format('copy (select c.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        where b.name=%L) to ''%s/commit.csv''', bundle_name, directory);
    execute format('copy (select r.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id 
        where b.name=%L) to ''%s/rowset.csv''', bundle_name, directory);
    execute format('copy (select rr.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id 
        join bundle.rowset_row rr on rr.rowset_id=r.id 
        where b.name=%L) to ''%s/rowset_row.csv''', bundle_name, directory);
    execute format('copy (select rrf.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id 
        join bundle.rowset_row rr on rr.rowset_id=r.id 
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id 
        where b.name=%L) to ''%s/rowset_row_field.csv''', bundle_name, directory);
    execute format('copy (select rrf.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id 
        join bundle.rowset_row rr on rr.rowset_id=r.id 
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id 
        where b.name=%L) to ''%s/rowset_row_field.csv''', bundle_name, directory);
    execute format('copy (select blob.* from bundle.bundle b
        join bundle.commit c on c.bundle_id=b.id
        join bundle.rowset r on c.rowset_id=r.id 
        join bundle.rowset_row rr on rr.rowset_id=r.id 
        join bundle.rowset_row_field rrf on rrf.rowset_row_id=rr.id 
        join bundle.blob on rrf.value_hash=blob.hash 
        where b.name=%L) to ''%s/blob.csv''', bundle_name, directory);
    execute format('copy (select ir.* from bundle.bundle b
        join bundle.ignored_row ir on ir.bundle_id=b.id
        where b.name=%L) to ''%s/ignored_row.csv''', bundle_name, directory);
end
$$;


create or replace function bundle.bundle_import_csv(directory text)
 returns void
 language plpgsql
as $$
begin
    execute format('alter table bundle.bundle disable trigger all');
    execute format('alter table bundle.commit disable trigger all');
    execute format('copy bundle.bundle from ''%s/bundle.csv''', directory);
    execute format('copy bundle.commit from ''%s/commit.csv''', directory);
    execute format('copy bundle.rowset from ''%s/rowset.csv''', directory);
    execute format('copy bundle.rowset_row from ''%s/rowset_row.csv''', directory);
    execute format('copy bundle.blob from ''%s/blob.csv''', directory);
    execute format('copy bundle.rowset_row_field from ''%s/rowset_row_field.csv''', directory);
    execute format('copy bundle.ignored_row from ''%s/ignored_row.csv''', directory);
    execute format('alter table bundle.bundle enable trigger all');
    execute format('alter table bundle.commit enable trigger all');
end
$$;

create or replace function garbage_collect ( ) returns void 
as $$
delete from bundle.blob where hash is null;
delete from bundle.rowset_row_field where value_hash is null;
delete from bundle.blob where hash not in (select value_hash from bundle.rowset_row_field);
delete from bundle.rowset where id not in (select rowset_id from bundle.commit);
$$ language sql;



commit;

