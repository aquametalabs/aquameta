-- export.sql
--
-- This script writes bundle repositories in the database to files.  It
-- additively updates the files with any additional commits.  It will run
-- from within postgresql, with the permissions of the user running the
-- postgresql server, so the bundle directories need to be writable by
-- that user.

-- core modules
select bundle.bundle_export_csv('org.aquameta.core.bundle','/s/aquameta/bundles-available/org.aquameta.core.bundle');
select bundle.bundle_export_csv('org.aquameta.core.event','/s/aquameta/bundles-available/org.aquameta.core.event');
select bundle.bundle_export_csv('org.aquameta.core.filesystem','/s/aquameta/bundles-available/org.aquameta.core.filesystem');
select bundle.bundle_export_csv('org.aquameta.core.http_client','/s/aquameta/bundles-available/org.aquameta.core.http_client');
select bundle.bundle_export_csv('org.aquameta.core.www','/s/aquameta/bundles-available/org.aquameta.core.www');
select bundle.bundle_export_csv('org.aquameta.core.meta','/s/aquameta/bundles-available/org.aquameta.core.meta');
select bundle.bundle_export_csv('org.aquameta.core.p2p','/s/aquameta/bundles-available/org.aquameta.core.p2p');
select bundle.bundle_export_csv('org.aquameta.core.widget','/s/aquameta/bundles-available/org.aquameta.core.widget');
select bundle.bundle_export_csv('org.aquameta.core.semantics','/s/aquameta/bundles-available/org.aquameta.core.semantics');

-- example modules
select bundle.bundle_export_csv('org.aquameta.games.snake','/s/aquameta/bundles-available/org.aquameta.games.snake');

-- TODO: re-organize these
select bundle.bundle_export_csv('org.aquameta.core.docs','/s/aquameta/bundles-available/org.aquameta.core.docs');
select bundle.bundle_export_csv('org.aquameta.core.ide','/s/aquameta/bundles-available/org.aquameta.core.ide');

-- user interface modules
select bundle.bundle_export_csv('org.aquameta.ui.fsm','/s/aquameta/bundles-available/org.aquameta.ui.fsm');
select bundle.bundle_export_csv('org.aquameta.ui.tags','/s/aquameta/bundles-available/org.aquameta.ui.tags');
