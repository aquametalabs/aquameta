reset
dropdb flat
createdb flat
cd meta/flat/
cat 0*.sql|psql flat
cd ../../bundle
cat 0*.sql|psql flat
cd ../endpoint
cat 000-data-model.sql 001-server.sql|psql flat
cd ../
cd ../
./aquameta -c conf/flat.toml


cd ~orchestrator/aquameta/bundles.private
./import.sh | psql flat
cd
cd dev/aquameta/extensions
cat bundle/migrate_flat.sql|psql flat

# export:
# select bundle.bundle_export_csv(b.name, bc.directory) from bundle.bundle b join bundle.bundle_csv bc on bc.bundle_id = b.id;
