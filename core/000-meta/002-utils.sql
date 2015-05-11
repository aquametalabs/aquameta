begin;

set search_path=meta;

create or replace function meta.construct_join_graph (temp_table_name text, start_rowset json, subrowsets json) returns void
as $$
declare
    tmp text;

    schema_name text;
    relation_name text;
    label text;
    local_id text;

    related_label text;
    related_field text;

    where_clause text;

    rowset json;
    q text;
begin
    -- create temp table
    tmp := quote_ident(temp_table_name);
    execute 'create temp table ' 
        || tmp
        || '(label text, row_id meta.row_id, row json)';

    -- load up the starting relation
    schema_name := quote_ident(start_rowset->>'schema_name');
    relation_name := quote_ident(start_rowset->>'relation_name');
    label := quote_ident(start_rowset->>'label');
    local_id:= quote_ident(start_rowset->>'local_id');

    where_clause := coalesce ('where ' || (start_rowset->>'where_clause')::text, '');

    raise notice '#### construct_join_graph PHASE 1:  label: %, schema_name: %, relation_name: %, local_id: %, where_clause: %', 
        label, schema_name, relation_name, local_id, where_clause;

    execute 'insert into ' || tmp
        || ' select ''' || label || ''','
        || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || local_id || ''',' || label || '.' || local_id || '::text), '
        || '     row_to_json(' || label || ')'
        || ' from ' || schema_name || '.' || relation_name || ' ' || label
        || ' ' where_clause;

    for i in 0..(json_array_length(subrowsets) - 1) loop
        rowset := subrowsets->i;
        
        schema_name := quote_ident(rowset->>'schema_name');
        relation_name := quote_ident(rowset->>'relation_name');
        label := quote_ident(rowset->>'label');
        local_id:= quote_ident(rowset->>'local_id');

        related_label := quote_ident(rowset->>'related_label');
        related_field := quote_ident(rowset->>'related_field');

        where_clause := coalesce ('where ' || (rowset->>'where_clause')::text, '');

        raise notice '#### construct_join_graph PHASE 2:  label: %, schema_name: %, relation_name: %, local_id: %, related_label: %, related_field: %, where_clause: %', 
            label, schema_name, relation_name, local_id, related_label, related_field, where_clause;


        q := 'insert into ' || tmp
            || ' select ''' || label || ''','
            || '     meta.row_id(''' || schema_name || ''',''' || relation_name || ''',''' || local_id || ''',' || label || '.' || local_id || '::text), '
            || '     row_to_json(' || label || ')'
            || ' from ' || schema_name || '.' || relation_name || ' ' || label
            || ' join ' || tmp || ' on ' || tmp || '.label = ''' || related_label || ''''
            || '  and (' || tmp || '.row)->>''' || related_field || ''' = ' || label || '.' || local_id || '::text'
            || ' ' || where_clause;
        raise notice 'QUERY: %', q;
        execute q;

            
    end loop;




end;
$$ language plpgsql;

select meta.construct_join_graph('foo', '{ "schema_name": "bundle", "relation_name": "bundle", "label": "b", "local_id": "id"}', 
    '[
        {"schema_name": "bundle", "relation_name": "commit", "label": "c", "local_id": "bundle_id", "related_label": "b", "related_field": "id"},
        {"schema_name": "bundle", "relation_name": "rowset", "label": "r", "local_id": "id", "related_label": "c", "related_field": "rowset_id"}
     ]');

commit;
