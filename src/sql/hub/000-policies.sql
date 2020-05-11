/*
security policies for a hub.

other things to do:
- in postgresql.conf, change listen_address = '*'
- in pg_hba.conf add
      host    all             all              0.0.0.0/0                       md5
    - host    all             all              ::/0                            md5
- open port 5432 to publc traffic
*/

alter role anonymous password 'anonymous';


/*
 * bundle privileges
 *
 */

-- base grant permissions
grant usage on schema bundle to anonymous;
grant select on all tables in schema bundle to anonymous;

-- rls privileges
alter table bundle.bundle enable row level security;
create policy anonymous_core_bundles on bundle.bundle for select to anonymous
    using (name like 'org.aquameta.%');

/*
grant select on table commit to anonymous;
grant select on table rowset to anonymous;
grant select on table rowset_row to anonymous;
grant select on table rowset_row_field to anonymous;
grant select on table blob to anonymous;
grant select on table ignored_row to anonymous;
grant select on table ignored_column to anonymous;
grant select on table ignored_relation to anonymous;
grant select on table ignored_schema to anonymous;
*/

/*
 * ui privileges
 *
 */

grant select on table widget.widget to anonymous;
