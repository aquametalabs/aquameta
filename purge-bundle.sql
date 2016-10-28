set search_path=bundle;

begin;

delete from blob;
delete from commit;
delete from stage_row_deleted;
delete from rowset;
delete from bundle;
delete from stage_field_changed;
delete from stage_row_added;
delete from stage_row_deleted;
delete from tracked_row_added;
delete from stage_row_added;
delete from stage_field_changed;

commit;
