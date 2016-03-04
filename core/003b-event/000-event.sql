/******************************************************************************
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

/************************************************************************
 * subscription tables
 * inserting into these tables attaches the 'evented' trigger to the
 * specified table, if necessary
 ***********************************************************************/

-- todo: add trigger that checks to see 
create table event.subscription_table (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references session.session(id) on delete cascade,
    relation_id meta.relation_id,
    created_at timestamp not null default now()
);

create table event.subscription_column (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references session.session(id) on delete cascade,
    column_id meta.column_id,
    created_at timestamp not null default now()
);


create table event.subscription_row (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references session.session(id) on delete cascade,
    row_id meta.row_id,
    created_at timestamp not null default now()
);

create table event.subscription_field (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references session.session(id) on delete cascade,
    field_id meta.field_id,
    created_at timestamp not null default now()
);


create view event.subscription as 
 select s.id,
    'table'::text as type,
    s.relation_id,
    NULL::meta.column_id as column_id,
    NULL::meta.row_id as row_id,
    NULL::meta.field_id as field_id
   from event.subscription_table s
union
 select s.id,
    'column'::text as type,
    NULL::meta.relation_id as relation_id,
    s.column_id,
    NULL::meta.row_id as row_id,
    NULL::meta.field_id as field_id
   from event.subscription_column s
union
 select s.id,
    'row'::text as type,
    NULL::meta.relation_id as relation_id,
    NULL::meta.column_id as column_id,
    s.row_id,
    NULL::meta.field_id as field_id
   from event.subscription_row s
union
 select s.id,
    'field'::text as type,
    NULL::meta.relation_id as relation_id,
    NULL::meta.column_id as column_id,
    NULL::meta.row_id as row_id,
    s.field_id
   from event.subscription_field s;


/************************************************************************
 * event
 * this holds sent (NOTIFY'ed) events, and the client is responsible for
 * deleting them upon receipt.  if the client disconnects, when it
 * reattaches, the reattach handler should blast out all the events that
 * the client has not yet deleted.
 ***********************************************************************/

create table event.event (
    id uuid default public.uuid_generate_v4() primary key,
    session_id uuid not null references session.session(id) on delete cascade,
    event json,
    created_at timestamp not null default now()
);


/************************************************************************
 * evented trigger
 * this is the trigger that gets attached to any table that someone
 * subscribes to.  it queries the subscription_* tables looking for
 * subscriptions that match this table and, when found, sends the
 * subscriber an event.
 ***********************************************************************/

create or replace function event.event_listener_table() returns trigger as $$
    declare
        event json; -- TODO: jsonb?
        row_id meta.row_id;
        event_receiver record;

        tmp_boolean boolean; -- This is stupid
        meta_column_row record; -- This also is a little stupid
    begin
        /* first, find the relation-level subscriptions (sub_table, sub_column) that match this TG_OP */
        /* subscription_table */
        for event_receiver in
            select s.*, r.schema_name::text, r.name::text, (r.primary_key_column_names[1]).name::text as pk
                    from meta.relation r 
                        join (
                            select s.id, s.session_id, 'table' as type, s.relation_id, null::meta.column_id
                            from subscription_table s

                            union

                            select s.id, s.session_id, 'column' as type, s.column_id::meta.relation_id, s.column_id
                            from subscription_column s

                            -- This prevents events being sent in multiplicate to repeat subscribers -- TODO better way
                            where s.session_id not in (select session_id from subscription_table)
                        ) s on s.relation_id=r.id

            where r.schema_name = TG_TABLE_SCHEMA
                and r.name = TG_TABLE_NAME

        loop
            -- DELETE
            if TG_OP = 'DELETE' then

                /* get the row_id deleted */
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using OLD;

                -- raise notice 'row_id: %', row_id::text;
                event := json_build_object('operation', 'delete', 'subscription_type', event_receiver.type, 'row_id', row_id);

                -- insert this event into the event table
                execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';
                perform pg_notify(event_receiver.session_id::text, event::text);

                --perform pg_notify(session.current_session_id()::text, event::text);
                --return OLD;
                continue;


            -- INSERT
            elsif TG_OP = 'INSERT' then

                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- raise notice 'row_id: %', row_id::text;
                event := json_build_object('operation', 'insert', 'subscription_type', event_receiver.type, 'row_id', row_id, 'payload', row_to_json(NEW));

                -- insert this event into the event table
                execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';
                perform pg_notify(event_receiver.session_id::text, event::text);

                --perform pg_notify(session.current_session_id()::text, event::text);
                --return NEW;
                continue;


            -- UPDATE
            elsif TG_OP = 'UPDATE' then

                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- Loop through columns
                <<meta_column_loop>>
                for meta_column_row in
                    select id from meta.column where relation_id = event_receiver.relation_id
                loop

                    -- Skip if wrong column
                    if event_receiver.type = 'column' and event_receiver.column_id <> meta_column_row.id then
                        continue meta_column_loop;
                    else

                        -- Only sending changed fields
                        -- Check to see if this column was updated, bail if not
                        execute 'select $1.' || (meta_column_row.id).name || ' is not distinct from $2.' || (meta_column_row.id).name using NEW, OLD into tmp_boolean;
                        if tmp_boolean then
                            --raise notice '---- columns are equal!!!!!! % ---- skipping ----', quote_literal((meta_column_row.id).name);
                            continue meta_column_loop;
                        end if;

                        -- Build payload of changed field
                        execute 
                            'select json_build_object(''operation'', ''update'', ''subscription_type'', ''' || event_receiver.type || ''', ''row_id'', $1, ''payload'', ' || 
                            '(select json_build_object(''' || (meta_column_row.id).name || ''', $2.' || (meta_column_row.id).name || ')));'
                            using row_id, NEW
                        into event;

                        -- insert this event into the event table
                        execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';
                        perform pg_notify(event_receiver.session_id::text, event::text);

                        continue meta_column_loop;

                    end if;

                end loop meta_column_loop;

                --return NEW;
                continue;

            end if;


        end loop;

        return NULL;


    end;
$$ language plpgsql;


/************************************************************************
 * function subscribe_table(relation_id)
 * adds a row to the subscription_table table, attaches the trigger
 ***********************************************************************/

 create or replace function event.subscribe_table(relation_id meta.relation_id) returns uuid as $$
    declare
        session_id uuid;
        trigger_name text := relation_id.name || '_evented_table';
    begin
        execute format ('drop trigger if exists %I on %I.%I', trigger_name, (relation_id.schema_id).name, relation_id.name);
        execute format ('create trigger %I '
            'after insert or update or delete on %I.%I '
            'for each row execute procedure event.event_listener_table()',
                trigger_name,
                (relation_id.schema_id).name,
                relation_id.name);

        insert into subscription_table(session_id, relation_id)
            values(session.current_session_id(),relation_id)
            returning id into session_id;
        return session_id;
    end;
$$ language plpgsql;



/************************************************************************
 * function subscribe_column(column_id)
 * adds a row to the subscription_column table, attaches the trigger
 ***********************************************************************/

 create or replace function event.subscribe_column(column_id meta.column_id) returns uuid as $$
    declare
        session_id uuid;
        relation_id meta.relation_id;
        trigger_name text;
    begin
        relation_id := column_id.relation_id;
        trigger_name := relation_id.name || '_evented_table';

        execute format ('drop trigger if exists %I on %I.%I', trigger_name, (relation_id.schema_id).name, relation_id.name);
        execute format ('create trigger %I '
            'after insert or update or delete on %I.%I '
            'for each row execute procedure event.event_listener_table()',
                trigger_name,
                (relation_id.schema_id).name,
                relation_id.name);

        insert into subscription_column(session_id, column_id)
            values(session.current_session_id(),column_id)
            returning id into session_id;
        return session_id;
    end;
$$ language plpgsql;

commit;
