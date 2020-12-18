drop schema semantics_test cascade;
create schema semantics_test;
set search_path=semantics_test;

create table test (id serial primary key, a_int integer, b_decimal decimal, c_text text, d_varchar varchar(255), e_uuid uuid);
create table test_item(id serial primary key, name text, test_id integer references test(id));

insert into test (id, a_int, b_decimal, c_text, d_varchar, e_uuid) values
(1, 123, 22.5, 'hello','howdy',public.uuid_generate_v4()),
(2, 456, 27.5, 'dang','wow',public.uuid_generate_v4());

insert into test_item(name, test_id) values ('beef',1);
insert into test_item(name, test_id) values ('pork chop',1);
insert into test_item(name, test_id) values ('chicken stip',1);
insert into test_item(name, test_id) values ('haggis',1);
insert into test_item(name, test_id) values ('dog',2);
insert into test_item(name, test_id) values ('cat',2);
