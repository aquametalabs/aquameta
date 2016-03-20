/******************************************************************************
 * Sessions
 * Cross-connection identifier for persistent state
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
 * session
 *
 * a cross-connection identifier for persistent state
 *
 ***********************************************************************/

-- persistent session object.
create table event.session (
    id uuid default public.uuid_generate_v4() primary key,
    owner_id meta.role_id not null, -- the owner's role
    connection_id meta.connection_id
);



-- create a new event.session
create or replace function event.session_create() returns uuid as $$
    declare
        session_id uuid;
    begin
        insert into event.session (owner_id, connection_id)
            values (meta.current_role_id(), meta.current_connection_id())
            returning id into session_id;
        return session_id;
    end;
$$ language plpgsql;



-- reattach to an existing session
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

        -- to not do?
        EXECUTE 'update event.session set connection_id=meta.current_connection_id() where id=' || quote_literal(session_id);
    END;
$$ language plpgsql;



create or replace function event.session_detach( session_id uuid ) returns void as $$
    begin
        execute 'unlisten "' || session_id || '"';
    end;
$$ language plpgsql;



create or replace function event.session_delete( session_id uuid ) returns void as $$
    begin
        execute 'delete from event.session where id=' || quote_literal(session_id);
    end;
$$ language plpgsql;



create or replace function event.current_session_id() returns uuid as $$
    select id from event.session where connection_id=meta.current_connection_id();
$$ language sql;


commit;
