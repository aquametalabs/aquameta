
echo 'begin;' > bundle-data-export.sql
pg_dump --schema=bundle --data-only aquameta >> bundle-data-export.sql
echo 'commit;' >> bundle-data-export.sql
