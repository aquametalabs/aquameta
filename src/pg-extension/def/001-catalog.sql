/*******************************************************************************
 * Definitions Catalog
 * A view for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/******************************************************************************
 * require_one and require_all()
 *****************************************************************************/
create function def.require_all(fields public.hstore, required_fields text[]) returns void as $$
    declare
        f record;

    begin
        -- hstore needs this
        set local search_path=public,def;
        for f in select unnest(required_fields) as field_name loop
            if (fields->f.field_name) is null then
                raise exception '% is a required field.', f.field_name;
            end if;
        end loop;
    end;
$$ language plpgsql;


create function def.require_one(fields public.hstore, required_fields text[]) returns void as $$
    declare
        f record;

    begin
        -- hstore needs this
        set local search_path=public,def;
        for f in select unnest(required_fields) as field_name loop
            if (fields->f.field_name) is not null then
                return;
            end if;
        end loop;

        raise exception 'One of the fields % is required.', required_fields;
    end;
$$ language plpgsql;




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





/******************************************************************************
 * def.type
 *****************************************************************************/

create view def.type as
select
    meta.type_id(typnamespace::regnamespace::text, typname::text) as id,
    pg_catalog.get_typedef(t.oid) as definition,
    t.typtype as "type"
from pg_catalog.pg_type t
where t.typtype = 'c'
    and meta.type_id(typnamespace::regnamespace::text, typname::text) not in (
        select id from meta.table
        union
        select id from meta.view
    );

create function def.stmt_type_create(definition text) returns text as $$
    select definition;
$$ language sql;


create function def.stmt_type_drop(type_id meta.type_id) returns text as $$
    select 'drop type ' ||
        quote_ident((type_id::meta.schema_id).name) || '.' ||
        quote_ident(type_id.name) || ';';
$$ language sql;


create function def.type_insert() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);

        execute def.stmt_type_create(NEW.definition);

        return NEW;
    end;
$$ language plpgsql;


create function def.type_update() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);

        execute def.stmt_type_drop(OLD.id);
        execute def.stmt_type_create(NEW.definition);

        return NEW;
    end;
$$ language plpgsql;


create function def.type_delete() returns trigger as $$
    begin
        execute def.stmt_type_drop(OLD.id);
        return OLD;
    end;
$$ language plpgsql;

create trigger def_type_insert_trigger instead of insert on def.type for each row execute procedure def.type_insert();
create trigger def_type_trigger instead of update on def.type for each row execute procedure def.type_update();
create trigger def_type_delete_trigger instead of delete on def.type for each row execute procedure def.type_delete();
