set search_path=bundle;

drop type if exists bundle.vid;
create type bundle.vid as (id uuid, commit_id uuid);

create or replace function bundle.vid_generate() returns bundle.vid as $$
declare vid bundle.vid;
begin
    vid.id := public.uuid_generate_v4();
    vid.commit_id := null;

    return vid;
end;
$$ language plpgsql;
