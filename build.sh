# dropdb aquameta
echo "Creating database ..."
createdb aquameta # --encoding UNICODE

echo "Loading requirements ..."
cat core/requirements.sql | psql aquameta

echo "Loading core/*.sql ..."
cat core/0*/0*.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

echo "Installing fs_fdw..."
cd core/002-filesystem/fs_fdw
./install_fs_fdw.sh
cd ../../../

echo "Loading bundles-enabled/*.sql ..."
cat bundles-enabled/*.sql | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

echo "Loading bundles-enabled/*/*.csv ..."
for D in `find $PWD/bundles-enabled/* \( -type l -o -type d \)`
do
    echo "select bundle.bundle_import_csv('$D')" | psql aquameta
done

echo "Checking out head commit of every bundle ..."
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta

echo "Loading default permissions ..."
cat core/default-permissions.sql  | psql -a aquameta 2>&1 | grep -B 2 -A 10 ERROR:

exit 0
