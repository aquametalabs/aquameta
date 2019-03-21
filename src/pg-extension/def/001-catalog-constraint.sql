/*******************************************************************************
 * Definitions Catalog
 * A constraint for every type of PostgreSQL object that contains it's definition statement
 *
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/


/******************************************************************************
 * def.constraint
 *****************************************************************************/

create constraint def.constraint as
select
    meta.constraint_id(schemaname::text, constraintname::text) as id,
    'create constraint ' || quote_ident(schemaname) || '.' || quote_ident(constraintname) || ' as '
        || pg_catalog.pg_get_constraintdef(quote_ident(schemaname) || '.' || quote_ident(constraintname)) as definition -- TODO switch to oid
from pg_catalog.pg_constraints v;

create function def.stmt_constraint_create(definition text) returns text as $$
    select definition;
$$ language sql;


create function def.stmt_constraint_drop(constraint_id meta.constraint_id) returns text as $$
    select 'drop constraint ' ||
        quote_ident((constraint_id::meta.schema_id).name) || '.' ||
        quote_ident(constraint_id.name) || ';';
$$ language sql;


create function def.constraint_insert() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);
        execute def.stmt_constraint_create(NEW.definition);
        return NEW;
    end;
$$ language plpgsql;


create function def.constraint_update() returns trigger as $$
    begin
        perform def.require_all(public.hstore(NEW), array['definition']);
        execute def.stmt_constraint_drop(OLD.id);
        execute def.stmt_constraint_create(NEW.definition);
        return NEW;
    end;
$$ language plpgsql;


create function def.constraint_delete() returns trigger as $$
    begin
        execute def.stmt_constraint_drop(OLD.id);
        return OLD;
    end;
$$ language plpgsql;

create trigger def_constraint_insert_trigger instead of insert on def.constraint for each row execute procedure def.constraint_insert();
create trigger def_constraint_trigger instead of update on def.constraint for each row execute procedure def.constraint_update();
create trigger def_constraint_delete_trigger instead of delete on def.constraint for each row execute procedure def.constraint_delete();
