-- export.sql
--
-- This script writes bundle repositories in the database to files.  It
-- additively updates the files with any additional commits.  It will run
-- from within postgresql, with the permissions of the user running the
-- postgresql server, so the bundle directories need to be writable by
-- that user.

-- core modules
select bundle.bundle_export_csv('org.aquameta.core.endpoint','/opt/aquameta/bundles-available/org.aquameta.core.endpoint');
select bundle.bundle_export_csv('org.aquameta.core.mimetypes','/opt/aquameta/bundles-available/org.aquameta.core.mimetypes');
select bundle.bundle_export_csv('org.aquameta.core.semantics','/opt/aquameta/bundles-available/org.aquameta.core.semantics');
select bundle.bundle_export_csv('org.aquameta.core.docs','/opt/aquameta/bundles-available/org.aquameta.core.docs');
select bundle.bundle_export_csv('org.aquameta.core.ide','/opt/aquameta/bundles-available/org.aquameta.core.ide');
select bundle.bundle_export_csv('org.aquameta.core.widget','/opt/aquameta/bundles-available/org.aquameta.core.widget');


-- example modules
select bundle.bundle_export_csv('org.aquameta.games.snake','/opt/aquameta/bundles-available/org.aquameta.games.snake');

-- user interface modules
select bundle.bundle_export_csv('org.aquameta.ui.admin','/opt/aquameta/bundles-available/org.aquameta.ui.admin');
select bundle.bundle_export_csv('org.aquameta.ui.auth','/opt/aquameta/bundles-available/org.aquameta.ui.auth');
select bundle.bundle_export_csv('org.aquameta.ui.bundle','/opt/aquameta/bundles-available/org.aquameta.ui.bundle');
select bundle.bundle_export_csv('org.aquameta.ui.dev','/opt/aquameta/bundles-available/org.aquameta.ui.dev');
select bundle.bundle_export_csv('org.aquameta.ui.event','/opt/aquameta/bundles-available/org.aquameta.ui.event');
select bundle.bundle_export_csv('org.aquameta.ui.fsm','/opt/aquameta/bundles-available/org.aquameta.ui.fsm');
select bundle.bundle_export_csv('org.aquameta.ui.layout','/opt/aquameta/bundles-available/org.aquameta.ui.layout');
select bundle.bundle_export_csv('org.aquameta.ui.tags','/opt/aquameta/bundles-available/org.aquameta.ui.tags');
select bundle.bundle_export_csv('org.aquameta.ui.p2p','/opt/aquameta/bundles-available/org.aquameta.ui.tags');
select bundle.bundle_export_csv('org.aquameta.templates.simple','/opt/aquameta/bundles-available/org.aquameta.templates.simple');
