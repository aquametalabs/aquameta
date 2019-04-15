set search_path=bundle;
insert into bundle.remote_database 
(foreign_server_name, schema_name, host, port, dbname, username, password)
values
('hub','hub','hub.aquameta.com',5432,'aquameta','anonymous','anonymous');
