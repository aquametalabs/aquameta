/*******************************************************************************
 * Definitions Catalog
 * A view for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/******************************************************************************
 * def.function
 *****************************************************************************/

create or replace view def.function as
select
    meta.function_id( pronamespace::pg_catalog.regnamespace::text, proname::text, regexp_split_to_array(pg_catalog.pg_get_function_arguments(p.oid),', ')) as id,
    pg_catalog.pg_get_functiondef_no_searchpath(p.oid) as definition
from pg_catalog.pg_proc p
where proisagg is false; -- why??  otherwise I get "ERROR:  "sum" is an aggregate function"


create function def.stmt_function_create(definition text) returns text as $$
    select definition;
$$ language sql;


create function def.stmt_function_drop(function_id meta.function_id) returns text as $$
    select 'drop function ' || quote_ident((function_id::meta.schema_id).name) || '.' || quote_ident(function_id.name) || '(' ||
               array_to_string(function_id.parameters, ',') ||
           ');';
$$ language sql;


create function def.function_insert() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);

        execute def.stmt_function_create(NEW.definition);

        return NEW;
    end;
$$ language plpgsql;


create function def.function_update() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);

        execute def.stmt_function_drop(OLD.id);
        execute def.stmt_function_create(NEW.definition);

        return NEW;
    end;
$$ language plpgsql;


create function def.function_delete() returns trigger as $$
    begin
        execute def.stmt_function_drop(OLD.id);
        return OLD;
    end;
$$ language plpgsql;

create trigger def_function_insert_trigger instead of insert on def.function for each row execute procedure def.function_insert();
create trigger def_function_trigger instead of update on def.function for each row execute procedure def.function_update();
create trigger def_function_delete_trigger instead of delete on def.function for each row execute procedure def.function_delete();
