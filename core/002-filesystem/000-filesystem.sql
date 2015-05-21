begin;
create schema filesystem;

set search_path=filesystem;


-- http://dba.stackexchange.com/questions/1742/how-to-insert-file-data-into-a-postgresql-bytea-column
create or replace function bytea_import(p_path text, p_result out bytea) 
language plpgsql as $$
declare
  l_oid oid;
  r record;
begin
  p_result := '';
  select lo_import(p_path) into l_oid;
  for r in ( select data 
             from pg_largeobject 
             where loid = l_oid 
             order by pageno ) loop
    p_result = p_result || r.data;
  end loop;
  perform lo_unlink(l_oid);
end;$$;

commit;
