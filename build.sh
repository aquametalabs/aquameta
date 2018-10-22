# dropdb aquameta
echo "Creating database ..."
createdb aquameta # --encoding UNICODE

echo "create role root superuser login;" | psql -U postgres postgres
echo "create role ubuntu superuser login;" | psql -U postgres postgres

createdb aquameta

echo "Building Aquameta core extensions..."

cd extensions && make && make install
cd ..

echo "Installing required extensions..."
cat extensions/requirements.sql | psql aquameta

# echo "Loading core/*.sql ..."
# cat core/0*/0*.sql  | psql aquameta

# echo "Loading bundles-enabled/*.sql ..."
# cat bundles-enabled/*.sql | psql aquameta

echo "Loading bundles-enabled/*/*.csv ..."
for D in `find /s/aquameta/bundles-enabled/* \( -type l -o -type d \)`
do
    echo "select bundle.bundle_import_csv('$D')" | psql aquameta
done

echo "Checking out head commit of every bundle ..."
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta

# Install FS FDW
echo "Installing filesystem foreign data wrapper..."
cd /s/aquameta/core/002-filesystem/fs_fdw
pip install . --upgrade
cat fs_fdw.sql | psql aquameta

echo "Loading default permissions..."
cd /s/aquameta
cat extensions/default-permissions.sql  | psql aquameta


exit 0
