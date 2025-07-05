
echo 'begin;' > tmp.sql
pg_dump --schema=bundle --data-only aquameta >> tmp.sql
sed '1,/^SET row_security = off;$/d' tmp.sql > bundle-data-export.sql
echo 'commit;' >> bundle-data-export.sql
