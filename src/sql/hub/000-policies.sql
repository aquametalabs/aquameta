/*
security policies for a hub.
this is just a stub.
*/

-- 
create policy anonymous_core_bundles on bundle.bundle for select to anonymous
    using (name like 'org.aquameta.%');

grant select on table widget.widget to anonymous;
