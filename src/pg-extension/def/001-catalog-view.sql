/*******************************************************************************
 * Definitions Catalog
 * A view for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/


/******************************************************************************
 * def.view
 *****************************************************************************/

create view def.view as
select
    meta.relation_id(schemaname::text, viewname::text) as id,
    pg_catalog.pg_get_viewdef(quote_ident(schemaname) || '.' || quote_ident(viewname)) as definition -- TODO switch to oid
from pg_catalog.pg_views v;

create function def.stmt_view_create(definition text) returns text as $$
    select definition;
$$ language sql;


create function def.stmt_view_drop(view_id meta.relation_id) returns text as $$
    select 'drop view ' ||
        quote_ident((view_id::meta.schema_id).name) || '.' ||
        quote_ident(view_id.name) || ';';
$$ language sql;


create function def.view_insert() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);
        execute def.stmt_view_create(NEW.definition);
        return NEW;
    end;
$$ language plpgsql;


create function def.view_update() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);
        execute def.stmt_view_drop(OLD.id);
        execute def.stmt_view_create(NEW.definition);
        return NEW;
    end;
$$ language plpgsql;


create function def.view_delete() returns trigger as $$
    begin
        execute def.stmt_view_drop(OLD.id);
        return OLD;
    end;
$$ language plpgsql;

create trigger def_view_insert_trigger instead of insert on def.view for each row execute procedure def.view_insert();
create trigger def_view_trigger instead of update on def.view for each row execute procedure def.view_update();
create trigger def_view_delete_trigger instead of delete on def.view for each row execute procedure def.view_delete();
