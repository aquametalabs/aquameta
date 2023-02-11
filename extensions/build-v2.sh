reset

# import the flattened stuff
dropdb flat
createdb flat
cat meta/flat/0*.sql|psql flat
cat bundle/0*.sql|psql flat
cd ../

# init the non-flat stuff
./aquameta -c conf/flat.toml

# import old private bundles
# cd ~orchestrator/aquameta/bundles.private
# ./import.sh | psql flat

# 
cd ~/dev/aquameta/extensions
cat bundle/migrate_flat.sql|psql flat

# export:
psql -c 'select bundle2.bundle_export_csv(b.name, bc.directory) from bundle2.bundle b join bundle2.bundle_csv bc on bc.bundle_id = b.id;' flat

# convert meta2 to meta, bundle2 to bundle
# sed -i 's/meta2/meta/g' meta/flat/0*.sql bundle/0*.sql
# sed -i 's/bundle2/bundle/g' meta/flat/0*.sql bundle/0*.sql

# repeat the "import the flat" step
# cat bundle/0*.sql|psql flat
# swap out main.go for main.go.no-install

