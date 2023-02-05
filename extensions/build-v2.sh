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
