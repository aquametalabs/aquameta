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
    begin
        /* first, find the relation-level subscriptions (sub_table, sub_column) that match this TG_OP */
        /* subscription_table */
        for event_receiver in
            select s.*, r.schema_name::text, r.name::text, (r.primary_key_column_names[1]).name::text as pk
                    from meta.relation r 
                        join (
                            select s.id, 'table' as type, s.relation_id, null::meta.column_id
                            from subscription_table s

                            union

                            select s.id, 'column', s.column_id::meta.relation_id, s.column_id
                            from subscription_column s
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
                -- todo: insert this event into the event table
                perform pg_notify(session.current_session_id()::text, event::text);
                return OLD;


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
                -- todo: insert this event into the event table
                perform pg_notify(session.current_session_id()::text, event::text);
                return NEW;


            -- UPDATE
            elsif TG_OP = 'UPDATE' then
                if event_receiver.type = 'column' then
                    -- todo: check to see if this column was updated, bail if not
                end if;

                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- raise notice 'row_id: %', row_id::text;
                event := json_build_object('operation', 'update', 'subscription_type', event_receiver.type, 'row_id', row_id, 'payload', row_to_json(NEW));
                -- todo: only send changed fields
                -- todo: insert this event into the event table
                perform pg_notify(session.current_session_id()::text, event::text);
                return NEW;
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
