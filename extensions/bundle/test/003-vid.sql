begin;

create schema vid_test;
set search_path=vid_test, bundle;

create table vendor (
    id vid not null default bundle.vid_generate() primary key,
    name text
);


create table product (
    id vid not null default bundle.vid_generate() primary key,
    name text,
    vendor_id vid references vendor(id),
    price decimal not null default 0
);


insert into vendor (name) values ('Wal-Mart');
insert into vendor (name) values ('Bi-Mart');


select bundle.bundle_create('pricedb');

-- bundle.stage_row_add(
commit;
