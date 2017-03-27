# dropdb aquameta
echo "Creating database ..."
createdb aquameta # --encoding UNICODE

echo "Loading requirements ..."
cat core/requirements.sql | psql aquameta

echo "Loading core/*.sql ..."
cat core/0*/0*.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

echo "Loading bundles-enabled/*.sql ..."
cat bundles-enabled/*.sql | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

echo "Checking out head commit of every bundle ..."
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta

echo "Loading default permissions ..."
cat core/004-aquameta_endpoint/default_permissions.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

exit 0
