-- export.sql
--
-- This script writes bundle repositories in the database to files.  It
-- additively updates the files with any additional commits.  It will run
-- from within postgresql, with the permissions of the user running the
-- postgresql server, so the bundle directories need to be writable by
-- that user.

-- core modules
select bundle.bundle_export_csv('org.aquameta.core.endpoint','/home/eric/aquameta/bundles-available/org.aquameta.core.endpoint');
select bundle.bundle_export_csv('org.aquameta.core.mimetypes','/home/eric/aquameta/bundles-available/org.aquameta.core.mimetypes');
select bundle.bundle_export_csv('org.aquameta.core.semantics','/home/eric/aquameta/bundles-available/org.aquameta.core.semantics');
select bundle.bundle_export_csv('org.aquameta.core.docs','/home/eric/aquameta/bundles-available/org.aquameta.core.docs');
select bundle.bundle_export_csv('org.aquameta.core.ide','/home/eric/aquameta/bundles-available/org.aquameta.core.ide');
select bundle.bundle_export_csv('org.aquameta.core.widget','/home/eric/aquameta/bundles-available/org.aquameta.core.widget');


-- example modules
select bundle.bundle_export_csv('org.aquameta.games.snake','/home/eric/aquameta/bundles-available/org.aquameta.games.snake');

-- user interface modules
select bundle.bundle_export_csv('org.aquameta.ui.admin','/home/eric/aquameta/bundles-available/org.aquameta.ui.admin');
select bundle.bundle_export_csv('org.aquameta.ui.auth','/home/eric/aquameta/bundles-available/org.aquameta.ui.auth');
select bundle.bundle_export_csv('org.aquameta.ui.bundle','/home/eric/aquameta/bundles-available/org.aquameta.ui.bundle');
select bundle.bundle_export_csv('org.aquameta.ui.dev','/home/eric/aquameta/bundles-available/org.aquameta.ui.dev');
select bundle.bundle_export_csv('org.aquameta.ui.event','/home/eric/aquameta/bundles-available/org.aquameta.ui.event');
select bundle.bundle_export_csv('org.aquameta.ui.fsm','/home/eric/aquameta/bundles-available/org.aquameta.ui.fsm');
select bundle.bundle_export_csv('org.aquameta.ui.layout','/home/eric/aquameta/bundles-available/org.aquameta.ui.layout');
select bundle.bundle_export_csv('org.aquameta.ui.tags','/home/eric/aquameta/bundles-available/org.aquameta.ui.tags');
select bundle.bundle_export_csv('org.aquameta.ui.template','/home/eric/aquameta/bundles-available/org.aquameta.ui.template');
