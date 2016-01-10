/*******************************************************************************
 * Events
 * Pub/sub event system for PostgreSQL
 * 
 * Created by Aquameta Labs in Portland, Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

begin;

create extension if not exists "uuid-ossp" schema public;

create schema event;

set search_path=event;

-- persistent session object.  
create table session (
    id uuid default public.uuid_generate_v4() primary key,
    owner_id meta.role_id not null -- , -- the postgresql user
--    connection_id meta.connection_id -- the postgresql database session
);


-- create a new event.session and listen to it's channel on this postgresql connection
create function event.session_create() returns void as $$
    declare
        session_id uuid;
    begin
        insert into event.session (owner_id) -- , connection_id)
            values (meta.current_role_id()) -- , meta.current_connection_id())
            returning id into session_id;
        execute 'listen "' || session_id || '"';
    end;
$$ language plpgsql;


-- reattach to an existing session
create function event.session_attach( session_id uuid ) returns void as $$
    begin
        -- todo: check to see that session exists
        execute 'listen "' || session_id || '"';
    end;
$$ language plpgsql;

create function event.session_detatch( session_id uuid ) returns void as $$
    begin
        execute 'unlisten "' || session_id || '"';
    end;
$$ language plpgsql;


/************************************************************************
 * subscription tables
 * inserting into these tables attaches the 'evented' trigger to the 
 * specified table, if necessary
 ***********************************************************************/

create table event.subscription_table (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id),
    relation_id meta.relation_id,
    created_at timestamp not null default now()
);

create table event.subscription_row (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id),
    row_id meta.row_id,
    created_at timestamp not null default now()
);

create table event.subscription_field (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id),
    field_id meta.field_id,
    created_at timestamp not null default now()
);

/****************************************************************************************************
 * TRIGGER subscription_selector                                                                    *
 ****************************************************************************************************/

create function event.evented() returns trigger as $$
    declare
        event_selector varchar;
        _event_type varchar;
        payload varchar := '';
        event_id uuid;
        s record;
        ret record;
        event_inserted bool := false;

    begin
        if TG_OP = 'DELETE' then
            _event_type := 'delete';
            payload := payload || ' "old": ' || row_to_json(OLD) || ',';

        elsif TG_OP = 'INSERT' then
            _event_type := 'insert';
            payload := payload || ' "new": ' || row_to_json(NEW) || ',';

        elsif TG_OP = 'UPDATE' then
            _event_type := 'update';
            payload := payload || ' "old": ' || row_to_json(OLD) || ','
                               || ' "new": ' || row_to_json(NEW) || ',';
        end if;

        payload := payload || '"columns":' || www.columns_json(
            TG_TABLE_SCHEMA::varchar,
            TG_TABLE_NAME::varchar
        );

        event_selector := TG_TABLE_SCHEMA || '/' || (
            select case relkind when 'r' then 'table'
                                else 'view'
                   end
            from pg_class
            where oid = TG_RELID
        ) || '/' || TG_TABLE_NAME || '/rows/' || case when TG_OP = 'DELETE' then OLD.id::text
                                                      else NEW.id::text
                                                 end;
        if TG_OP = 'DELETE' then
            ret := OLD;
        elsif TG_OP = 'INSERT' then
            ret := NEW;
        elsif TG_OP = 'UPDATE' then
            ret := NEW;
        end if;

        for s in
            select q.id as queue_id,
                   sub.id as subscription_id
            from event.queue q
            inner join event.subscription sub
                    on sub.queue_id = q.id
            where (sub.event_type = _event_type or sub.event_type = '*') and
                  event.selector_does_match(selector || ':' || sub.event_type, event_selector, public.hstore(ret))
        loop
            if not event_inserted then -- only insert the event if a subscription_selector is going to care about it
                insert into event.event (selector, "type", payload)
                values (event_selector, _event_type, ('{' || payload || '}')::json) returning id into event_id;
                
                event_inserted := true;
            end if;

            insert into event.queued_event (event_id, subscription_id)
            values (event_id, s.subscription_id);

            raise notice 'queue:%', s.queue_id;

            perform pg_notify('queue:' || s.queue_id, 'insert');
        end loop;

        return ret;
    end;
$$ language plpgsql;



/****************************************************************************************************
 * FUNCTION queued_events_json                                                                      *
 ****************************************************************************************************/

create function event.queued_events_json(
    _queue_id uuid,
    out queued_event_id uuid,
    out json json
) returns setof record as $$ -- FIXME: could be slow, be smarter about casting below
    select id as queued_event_id, ('{
        "method": "emit",
        "args": {
            "channels": ' || array_to_json(channels)::text || ',
            "selector": ' || to_json(selector)::text || ',
            "payload": ' || payload || '
        }
    }')::json as json

    from (
        select qe.id,
               array_agg((sub.selector || ':' || sub.event_type)) as channels,
               (e.selector || ':' || e.type) as selector,
               e.payload::text
        from event.queued_event qe
        inner join event.event e
                on e.id = qe.event_id
        inner join event.subscription sub
                on sub.id = qe.subscription_id
        where sub.queue_id = _queue_id
        group by qe.id,
                 e.selector,
                 e.type,
                 e.payload::text
    ) q
$$ language sql;



/****************************************************************************************************
 * VIEW evented_table                                                                               *
 ****************************************************************************************************/

create view event.evented_relation as
    select tr.schema_name,
           tr.relation_name
    from meta.trigger tr
    where ((tr.function_id).schema_id).name = 'event' and
          (tr.function_id).name = 'evented';

create function event.evented_relation_insert() returns trigger as $$
    begin
        insert into meta.trigger (relation_id, name, function_id, "when", "insert", "update", "delete", "level")
        values (
            (select r.id
             from meta."relation" r
             where r.schema_name = NEW.schema_name and
                   r.name = NEW.relation_name),
            quote_ident(NEW.schema_name) || '_' || quote_ident(NEW.relation_name) || '_event',
            (select f.id
             from meta."function" f
             where f.schema_name = 'event' and
                   f.name = 'evented'),
            'after', true, true, true, 'row'
        );

        return NEW;
    end;
$$ language plpgsql volatile;

create function event.evented_relation_update() returns trigger as $$
    declare
        old_table_id integer;
        new_table_id integer;
        function_id integer;

    begin
        select t.id
        from meta."table" t
        inner join meta.schema s
                on s.id = t.schema_id
        where s.name = OLD.schema_name and
              t.name = OLD.table_name
        into old_table_id;

        select t.id
        from meta."table" t
        inner join meta.schema s
                on s.id = t.schema_id
        where s.name = NEW.schema_name and
              t.name = NEW.table_name
        into new_table_id;

        select f.id
        from meta."function" f
        inner join meta.schema s
                on s.id = f.schema_id
        where s.name = 'event' and
              f.name = 'evented'
        into function_id;

        delete from meta.trigger
        where table_id = old_table_id and
              function_id = 'evented'::regproc;

        insert into meta.trigger (table_id, name, function_id, "when", "insert", "update", "delete", "level")
        values (
            new_table_id,
            quote_ident(NEW.schema_name) || '_' || quote_ident(NEW.table_name) || '_event',
            function_id,
            'after',
            true,
            true,
            true,
            'row'
        );

        return NEW;
    end;
$$ language plpgsql volatile;

create function event.evented_relation_delete() returns trigger as $$
    declare
        _table_id integer;
        _function_id integer;

    begin
        select t.id
        from meta."table" t
        inner join meta.schema s
                on s.id = t.schema_id
        where s.name = OLD.schema_name and
              t.name = OLD.table_name
        into _table_id;

        select f.id
        from meta."function" f
        inner join meta.schema s
                on s.id = f.schema_id
        where s.name = 'event' and
              f.name = 'evented'
        into _function_id;

        delete from meta.trigger
        where table_id = _table_id and
              function_id = _function_id;

        return OLD;
    end;
$$ language plpgsql volatile;

create trigger event_evented_relation_insert_trigger instead of insert on event.evented_relation for each row execute procedure event.evented_relation_insert();
create trigger event_evented_relation_update_trigger instead of update on event.evented_relation for each row execute procedure event.evented_relation_update();
create trigger event_evented_relation_delete_trigger instead of delete on event.evented_relation for each row execute procedure event.evented_relation_delete();



/****************************************************************************************************
 * FUNCTION selector_does_match                                                               *
 ****************************************************************************************************/

create function event.selector_does_match(
    selector1 varchar,
    selector2 varchar,
    row_data public.hstore
) returns bool as $$
    declare
        selector1_parts varchar[];
        selector2_parts varchar[];
        selector1_event varchar;
        selector2_event varchar;
        selector1_path_qs varchar;
        selector2_path_qs varchar;
        selector1_path varchar;
        selector2_path varchar;
        selector1_predicate_unsplit varchar[];
        selector2_predicate_unsplit varchar[];
        selector1_predicate public.hstore := ''::public.hstore;
        selector2_predicate public.hstore := ''::public.hstore;
        selector_predicate_split varchar[];
        item varchar;

    begin
        set local search_path = "public";

        selector1_parts := regexp_split_to_array(selector1, E':');
        selector2_parts := regexp_split_to_array(selector2, E':');

        selector1_path_qs := selector1_parts[1];
        selector2_path_qs := selector2_parts[1];

        selector1_event := selector1_parts[2];
        selector2_event := selector2_parts[2];

        selector1_parts := regexp_split_to_array(selector1_path_qs, E'\\?');
        selector2_parts := regexp_split_to_array(selector2_path_qs, E'\\?');

        selector1_path := selector1_parts[1];
        selector2_path := selector2_parts[1];

        if array_length(selector1_parts, 1) = 2 then
            selector1_predicate_unsplit = regexp_split_to_array(selector1_parts[2], E'\\&');
        else
            selector1_predicate_unsplit = '{}';
        end if;

        if array_length(selector2_parts, 1) = 2 then
            selector2_predicate_unsplit = regexp_split_to_array(selector2_parts[2], E'\\&');
        else
            selector2_predicate_unsplit = '{}';
        end if;

        if substr(selector2_path, 1, char_length(selector1_path)) != selector1_path then
            return false;
        end if;

        if selector2_event != selector1_event and selector1_event != '*' then
             return false;
        end if;

        foreach item in array selector1_predicate_unsplit
        loop
            selector_predicate_split := regexp_split_to_array(item, '=');
            selector1_predicate := selector1_predicate || (selector_predicate_split[1] || '=>' || selector_predicate_split[2])::public.hstore;

            if row_data -> selector_predicate_split[1] != selector_predicate_split[2] then
                return false;   
            end if;
        end loop;

        foreach item in array selector2_predicate_unsplit
        loop
            selector_predicate_split := regexp_split_to_array(item, '=');
            selector2_predicate := selector2_predicate || (selector_predicate_split[1] || '=>' || selector_predicate_split[2])::public.hstore;

            if selector1_predicate -> selector_predicate_split[1] != selector_predicate_split[2] then
                return false;
            end if;
        end loop;

        return true;
    end;
$$ language plpgsql;

/*
create function selector_does_match(selector1 varchar, selector2 varchar, row_data public.hstore) returns bool as $$
    declare
        selector1_parts varchar[];
        selector2_parts varchar[];
        selector1_path_parts varchar[];
        selector2_path_parts varchar[];
        selector1_event varchar;
        selector2_event varchar;
        selector1_path_qs varchar;
        selector2_path_qs varchar;
        selector1_path varchar;
        selector2_path varchar;
        selector1_predicate_unsplit varchar[];
        selector2_predicate_unsplit varchar[];
        selector1_predicate public.hstore := ''::public.hstore;
        selector2_predicate public.hstore := ''::public.hstore;
        selector_predicate_split varchar[];
        item varchar;

    begin
        set local search_path = "public";

        selector1_parts := regexp_split_to_array(selector1, E':');
        selector2_parts := regexp_split_to_array(selector2, E':');

        selector1_path_qs := selector1_parts[1];
        selector2_path_qs := selector2_parts[1];

        selector1_event := selector1_parts[2];
        selector2_event := selector2_parts[2];

        selector1_parts := regexp_split_to_array(selector1_path_qs, E'\\?');
        selector2_parts := regexp_split_to_array(selector2_path_qs, E'\\?');

        selector1_path := selector1_parts[1];
        selector2_path := selector2_parts[1];

        selector1_path_parts := string_to_array(selector1_path, '/');
        selector2_path_parts := string_to_array(selector2_path, '/');

        if array_length(selector1_parts, 1) = 2 then
            selector1_predicate_unsplit = regexp_split_to_array(selector1_parts[2], E'\\&');
        else
            selector1_predicate_unsplit = '{}';
        end if;

        if array_length(selector2_parts, 1) = 2 then
            selector2_predicate_unsplit = regexp_split_to_array(selector2_parts[2], E'\\&');
        else
            selector2_predicate_unsplit = '{}';
        end if;

        if not
            (select true = all(array_agg(item1=item2))
             from (
                 select unnest(selector1_path_parts) item1,
                        unnest(selector2_path_parts[1:array_length(selector1_path_parts, 1)]) item2
             ) q)
        then
            return false;
        end if;

        if selector2_event != selector1_event and selector1_event != '*' then
             return false;
        end if;

        foreach item in array selector1_predicate_unsplit
        loop
            selector_predicate_split := regexp_split_to_array(item, '=');
            selector1_predicate := selector1_predicate || (selector_predicate_split[1] || '=>' || selector_predicate_split[2])::public.hstore;

            if row_data -> selector_predicate_split[1] != selector_predicate_split[2] then
                return false;   
            end if;
        end loop;

        foreach item in array selector2_predicate_unsplit
        loop
            selector_predicate_split := regexp_split_to_array(item, '=');
            selector2_predicate := selector2_predicate || (selector_predicate_split[1] || '=>' || selector_predicate_split[2])::public.hstore;

            if selector1_predicate -> selector_predicate_split[1] != selector_predicate_split[2] then
                return false;
            end if;
        end loop;

        return true;
    end;
$$ language plpgsql;
*/



commit;
