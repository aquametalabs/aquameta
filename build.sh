# dropdb aquameta
createdb aquameta
cat core/0*/0*.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:
cat core/0*/semantics.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:
# cat scripts-enabled/*.sql | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:
cat bundles-enabled/*.sql | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta
