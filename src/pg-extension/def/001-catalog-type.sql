/*******************************************************************************
 * Definitions Catalog
 * A view for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/


/******************************************************************************
 * def.type
 *****************************************************************************/

create view def.type as
select
    meta.type_id(typnamespace::regnamespace::text, typname::text) as id,
    pg_catalog.pg_get_typedef(t.oid) as definition,
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
