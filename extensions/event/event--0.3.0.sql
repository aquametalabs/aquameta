/******************************************************************************
 * Events
 * Pub/sub event system for PostgreSQL
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/************************************************************************
 * table event.session
 * persistent (cross-connection) session object.
 ***********************************************************************/

create table event.session (
    id uuid not null default public.uuid_generate_v4() primary key,
    owner_id meta.role_id not null -- the owner's role
);


/************************************************************************
 * function event.session_create()
 * create a new event.session
 ***********************************************************************/

create or replace function event.session_create() returns uuid as $$
    declare
        session_id uuid;
    begin
        insert into event.session (owner_id)
            values (meta.current_role_id())
            returning id into session_id;
        return session_id;
    end;
$$ language plpgsql;


/************************************************************************
 * function event.session_attach()
 * attach to an existing session
 ***********************************************************************/

create or replace function event.session_attach( session_id uuid ) returns void as $$
    DECLARE
        session_exists boolean;
        event json; -- todo jsonb
    BEGIN

        EXECUTE 'select exists(select 1 from event.session where id=' || quote_literal(session_id) || ')' INTO session_exists;

        IF session_exists THEN

            EXECUTE 'LISTEN "' || session_id || '"';

            -- Send all events in the event table for this session (because they haven't yet been deleted aka recieved by the client)
            FOR event IN
                EXECUTE 'select event from event.event where session_id=' || quote_literal(session_id)
            LOOP
                EXECUTE 'NOTIFY "' || session_id || '",' || quote_literal(event);
            END LOOP;
        END IF;

    END;
$$ language plpgsql;


/************************************************************************
 * function event.session_detach()
 * detach from an existing session
 ***********************************************************************/

create or replace function event.session_detach( session_id uuid ) returns void as $$
    begin
        execute 'unlisten "' || session_id || '"';
    end;
$$ language plpgsql;


/************************************************************************
 * function event.session_delete()
 * delete from a session
 ***********************************************************************/

create or replace function event.session_delete( session_id uuid ) returns void as $$
    begin
        execute 'delete from event.session where id=' || quote_literal(session_id);
    end;
$$ language plpgsql;


/************************************************************************
 * subscription tables
 * inserting into these tables attaches the 'evented' trigger to the
 * specified table, if necessary
 ***********************************************************************/

-- todo: add trigger that checks to see
create table event.subscription_table (
    id uuid not null default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id) on delete cascade,
    relation_id meta.relation_id,
    created_at timestamp not null default now()
);

create table event.subscription_column (
    id uuid not null default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id) on delete cascade,
    column_id meta.column_id,
    created_at timestamp not null default now()
);


create table event.subscription_row (
    id uuid not null default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id) on delete cascade,
    row_id meta.row_id,
    created_at timestamp not null default now()
);

create table event.subscription_field (
    id uuid not null default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id) on delete cascade,
    field_id meta.field_id,
    created_at timestamp not null default now()
);


/************************************************************************
 * view event.subscription
 ***********************************************************************/

create view event.subscription as
 select s.id,
    s.session_id,
    'table'::text as type,
    s.relation_id,
    NULL::meta.column_id as column_id,
    NULL::meta.row_id as row_id,
    NULL::meta.field_id as field_id
   from event.subscription_table s
union
 select s.id,
    s.session_id,
    'column'::text as type,
    NULL::meta.relation_id as relation_id,
    s.column_id,
    NULL::meta.row_id as row_id,
    NULL::meta.field_id as field_id
   from event.subscription_column s
union
 select s.id,
    s.session_id,
    'row'::text as type,
    NULL::meta.relation_id as relation_id,
    NULL::meta.column_id as column_id,
    s.row_id,
    NULL::meta.field_id as field_id
   from event.subscription_row s
union
 select s.id,
    s.session_id,
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
    id uuid not null default public.uuid_generate_v4() primary key,
    session_id uuid not null references event.session(id) on delete cascade,
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

        tmp_boolean boolean;
        meta_column_row record;

    begin
        -- Loop through the relation-level subscriptions (sub_table, sub_column) that match this TG_OP
        for event_receiver in
            select distinct on (s.session_id) -- No duplicates
                s.*,
                r.schema_name::text,
                r.name::text,
                (r.primary_key_column_names[1]).name::text as pk
            from meta.relation r
                join (

                    select s.id, s.session_id, 'table' as type, s.relation_id, null::meta.column_id
                    from event.subscription_table s

                    union

                    select s.id, s.session_id, 'column' as type, s.column_id::meta.relation_id, s.column_id
                    from event.subscription_column s

                ) s on s.relation_id = r.id

            where r.schema_name = TG_TABLE_SCHEMA
                and r.name = TG_TABLE_NAME

            order by s.session_id, s.type desc

        loop
            -- DELETE
            if TG_OP = 'DELETE' then

                -- Get the row_id deleted
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using OLD;

                -- Build event payload
                event := json_build_object('operation', 'delete', 'subscription_type', event_receiver.type, 'row_id', row_id);

                -- Insert this event into the event table
                execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';

                -- Notify
                perform pg_notify(event_receiver.session_id::text, event::text);

                continue;


            -- INSERT
            elsif TG_OP = 'INSERT' then

                -- Get the row_id inserted
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- Build event payload
                event := json_build_object('operation', 'insert', 'subscription_type', event_receiver.type, 'row_id', row_id, 'payload', row_to_json(NEW));

                -- Insert this event into the event table
                execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';

                -- Notify
                perform pg_notify(event_receiver.session_id::text, event::text);

                continue;


            -- UPDATE
            elsif TG_OP = 'UPDATE' then

                -- Get the row_id updated
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- Loop through columns
                for meta_column_row in
                    select id from meta.column where relation_id = event_receiver.relation_id
                loop

                    -- Skip if wrong column
                    if event_receiver.type = 'column' and event_receiver.column_id <> meta_column_row.id then
                        continue;
                    else

                        -- Check to see if this column was updated, continue to next column if not
                        execute 'select $1.' || (meta_column_row.id).name || ' is not distinct from $2.' || (meta_column_row.id).name using NEW, OLD into tmp_boolean;
                        if tmp_boolean then
                            continue;
                        end if;

                        -- Build payload of changed field
                        execute
                            'select json_build_object(''operation'', ''update'', ''subscription_type'', ''' || event_receiver.type || ''', ''row_id'', $1, ''payload'', ' ||
                            '(select json_build_object(''' || (meta_column_row.id).name || ''', $2.' || (meta_column_row.id).name || ')));'
                            using row_id, NEW
                        into event;

                        -- Insert this event into the event table
                        execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';

                        -- Notify
                        perform pg_notify(event_receiver.session_id::text, event::text);

                        continue;

                    end if;

                end loop;

                continue;

            end if;


        end loop;

        return NULL;


    end;
$$ language plpgsql;



/************************************************************************
 * evented trigger row
 ***********************************************************************/

create or replace function event.event_listener_row() returns trigger as $$

    declare
        event json; -- TODO: jsonb?
        row_id meta.row_id;
        event_receiver record;

        tmp_boolean boolean;
        meta_column_row record;

    begin
        -- Loop through the row-level subscriptions (sub_row, sub_field) that match this TG_OP
        for event_receiver in
            select distinct on (session_id) -- No duplicates
                s.*,
                r.schema_name::text,
                r.name::text,
                (r.primary_key_column_names[1]).name::text as pk
            from meta.relation r
                join (

                    select s.id, s.session_id, 'row' as type, s.row_id, null::meta.field_id
                    from event.subscription_row s

                    union

                    select s.id, s.session_id, 'field' as type, (s.field_id).row_id, s.field_id
                    from event.subscription_field s

                ) s on s.row_id::meta.relation_id=r.id

            where r.schema_name = TG_TABLE_SCHEMA
                and r.name = TG_TABLE_NAME

            order by s.session_id, s.type desc


        loop

            -- Need to make sure this is the correct row
            execute 'select $1.' || event_receiver.pk || ' is distinct from ' || (event_receiver.row_id).pk_value using OLD into tmp_boolean;
            if tmp_boolean then
                return null;
            end if;

            -- DELETE
            if TG_OP = 'DELETE' then

                -- Get the row_id deleted
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using OLD;

                -- Build event payload
                event := json_build_object('operation', 'delete', 'subscription_type', event_receiver.type, 'row_id', row_id);

                -- Insert this event into the event table
                execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';

                -- Notify
                perform pg_notify(event_receiver.session_id::text, event::text);

                continue;

            elsif TG_OP = 'UPDATE' then

                -- Get the row_id deleted
                execute format('select * from meta.row_id(%L,%L,%L,($1).%I::text)',
                    event_receiver.schema_name,
                    event_receiver.name,
                    event_receiver.pk,
                    event_receiver.pk)
                into row_id
                using NEW;

                -- Loop through columns
                for meta_column_row in
                    select id from meta.column where relation_name = event_receiver.name and schema_name = event_receiver.schema_name
                loop

                    -- Skip if wrong column
                    if event_receiver.type = 'field' and (event_receiver.field_id).column_id <> meta_column_row.id then
                        continue;
                    else

                        -- Check to see if this column was updated, continue to next column if not
                        execute 'select $1.' || (meta_column_row.id).name || ' is not distinct from $2.' || (meta_column_row.id).name using NEW, OLD into tmp_boolean;
                        if tmp_boolean then
                            continue;
                        end if;

                        -- Build payload of changed field
                        execute
                            'select json_build_object(''operation'', ''update'', ''subscription_type'', ''' || event_receiver.type || ''', ''row_id'', $1, ''payload'', ' ||
                            '(select json_build_object(''' || (meta_column_row.id).name || ''', $2.' || (meta_column_row.id).name || ')));'
                            using row_id, NEW
                        into event;

                        -- Insert this event into the event table
                        execute 'insert into event.event(session_id, event) values(' || quote_literal(event_receiver.session_id) || ',' || quote_literal(event) || ')';

                        -- Notify
                        perform pg_notify(event_receiver.session_id::text, event::text);

                        continue;

                    end if;

                end loop;

                continue;

            end if;

        end loop;

        return NULL;

    end;
$$ language plpgsql;


/************************************************************************
 * function subscribe_table(session_id, relation_id)
 * adds a row to the subscription_table table, attaches the trigger
 ***********************************************************************/

create or replace function event.subscribe_table(
    session_id uuid,
    relation_id meta.relation_id
) returns void as $$

    declare
        trigger_name text := relation_id.name || '_evented_table';

    begin
        execute format ('drop trigger if exists %I on %I.%I', trigger_name, (relation_id.schema_id).name, relation_id.name);
        execute format ('create trigger %I '
            'after insert or update or delete on %I.%I '
            'for each row execute procedure event.event_listener_table()',
                trigger_name,
                (relation_id.schema_id).name,
                relation_id.name);

        insert into event.subscription_table(session_id, relation_id)
            values(session_id, relation_id);

    end;
$$ language plpgsql security definer;


/************************************************************************
 * function subscribe_column(session_id, column_id)
 * adds a row to the subscription_column table, attaches the trigger
 ***********************************************************************/

create or replace function event.subscribe_column(
    session_id uuid,
    column_id meta.column_id
) returns void as $$

    declare
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

        insert into event.subscription_column(session_id, column_id)
            values(session_id, column_id);

    end;
$$ language plpgsql security definer;


/************************************************************************
 * function subscribe_row(session_id, row_id)
 * adds a row to the subscription_row table, attaches the trigger
 ***********************************************************************/

create or replace function event.subscribe_row(
    session_id uuid,
    row_id meta.row_id
) returns void as $$

    declare
        relation_id meta.relation_id;
        trigger_name text;

    begin
        relation_id := (row_id.pk_column_id).relation_id;
        trigger_name := relation_id.name || '_evented_row';

        execute format ('drop trigger if exists %I on %I.%I', trigger_name, (relation_id.schema_id).name, relation_id.name);
        execute format ('create trigger %I '
            'after update or delete on %I.%I '
            'for each row execute procedure event.event_listener_row()',
                trigger_name,
                (relation_id.schema_id).name,
                relation_id.name);

        insert into event.subscription_row(session_id, row_id)
            values(session_id, row_id);

    end;
$$ language plpgsql security definer;


/************************************************************************
 * function subscribe_field(session_id, field_id)
 * adds a field to the subscription_field table, attaches the trigger
 ***********************************************************************/

create or replace function event.subscribe_field(
    session_id uuid,
    field_id meta.field_id
) returns void as $$

    declare
        relation_id meta.relation_id;
        trigger_name text;

    begin
        relation_id := (field_id.column_id).relation_id;
        trigger_name := relation_id.name || '_evented_row';

        execute format ('drop trigger if exists %I on %I.%I', trigger_name, (relation_id.schema_id).name, relation_id.name);
        execute format ('create trigger %I '
            'after update or delete on %I.%I '
            'for each row execute procedure event.event_listener_row()',
                trigger_name,
                (relation_id.schema_id).name,
                relation_id.name);

        insert into event.subscription_field(session_id, field_id)
            values(session_id, field_id);

    end;
$$ language plpgsql security definer;
