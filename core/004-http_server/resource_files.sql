begin;

set search_path=endpoint;

-- Some default mounted files
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-http_server/js/Datum.js', '/Datum.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-http_server/js/jQuery.min.js', '/jQuery.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-http_server/js/system.js', '/system.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-http_server/js/system-polyfills.js', '/system-polyfills.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-http_server/js/doT.min.js', '/doT.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/007-widget/js/widget.js', '/widget.js');
insert into resource_file(file_id, url) values ('/s/aquameta/Dockerfile', '/Dockerfile');
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core/004-http_server/js', false);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core', true);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta', true);


commit;
