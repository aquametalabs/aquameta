begin;

set search_path=endpoint;

-- Some default mounted files
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/Datum.js', '/Datum.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/jQuery.min.js', '/jQuery.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/system.js', '/system.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/system-polyfills.js', '/system-polyfills.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/004-aquameta_endpoint/js/doT.min.js', '/doT.min.js');
insert into resource_file(file_id, url) values ('/s/aquameta/core/007-widget/js/widget.js', '/widget.js');
insert into resource_file(file_id, url) values ('/s/aquameta/Dockerfile', '/Dockerfile');
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core/004-aquameta_endpoint/js', false);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta/core', true);
insert into resource_directory(directory_id, indexes) values ('/s/aquameta', true);


commit;
