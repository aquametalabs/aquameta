begin;

create extension if not exists pgtap schema public;
set search_path=public,event;

-- select plan(115);
select * from no_plan();

\set session_id '99719ae1-02bd-43be-9598-0586985bd964'

insert into session (id, owner_id) values (:session_id, meta.current_role_id());

-- test data
create table chakra (
    id serial primary key,
    position integer,
    name text,
    color text,
    tone_hz decimal
);
insert into chakra (id, position, name, color, tone_hz) values
    (1, 1, 'Root',         'red', 172.06),
    (2, 2, 'Navel',        'orange', 221.23),
    (3, 3, 'Solar Plexus', 'yellow', 141.27),
    (4, 4, 'Heart',        'green', 136.10)
;

select subscribe_table(meta.relation_id('event','chakra'));

insert into chakra (id, position, name, color, tone_hz) values
    (5, 5, 'I dont know',        'cyan', 157.10)
;

rollback;

