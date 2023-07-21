SET CONSTRAINTS ALL DEFERRED;

insert into bundle2.bundle select * from bundle.bundle;

insert into bundle2.blob select * from bundle.blob;
insert into bundle2.rowset select * from bundle.rowset;
insert into bundle2.rowset_row select r.id, r.rowset_id, 
meta2.row_id(
    ((r.row_id)::meta.schema_id).name,
    ((r.row_id)::meta.relation_id).name,
    ((r.row_id).pk_column_id).name,
    (r.row_id).pk_value
) from bundle.rowset_row r;

insert into bundle2.rowset_row_field select f.id, f.rowset_row_id,
meta2.field_id(
    ((f.field_id)::meta.schema_id).name,
    ((f.field_id)::meta.relation_id).name,
    (((f.field_id).row_id).pk_column_id).name,
    ((f.field_id).row_id).pk_value,
    ((f.field_id).column_id).name
),
value_hash from bundle.rowset_row_field f;

insert into bundle2.commit select id,bundle_id,rowset_id,null,parent_id,time,message from bundle.commit;

insert into bundle2.bundle_csv select * from bundle.bundle_csv;
