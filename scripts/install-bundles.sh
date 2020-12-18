
#############################################################################
# install and checkout enabled bundles
#############################################################################
echo "Installing core bundles..."

echo "Please choose:"
echo "  a) Hub installl -- download bundles (and future updates)"
echo "     from the Aquameta bundle hub."
echo "  b) Offline install -- do not connect to the hub, install"
echo "     from source only."
REPLY=
while ! [[ $REPLY =~ ^[aAbB]$ ]]
do
	echo
	read -p "[A/b] " -n 1 -r
done

if [[ $REPLY =~ ^[bB]$ ]]
then
	if [ "$DEST" != "$SRC" ]; then
	    mkdir --parents $DEST
	    cp -R $SRC/bundles-available $DEST
	    cp -R $SRC/bundles-enabled $DEST
	fi

#	chown -R postgres:postgres $DEST/bundles-available
#	chown -R postgres:postgres $DEST/bundles-enabled

	echo "Loading bundles-enabled/*/*.csv ..."
	for D in `find $DEST/bundles-enabled/* \( -type l -o -type d \)`
	do
	    sudo -u postgres psql -c "select bundle.bundle_import_csv('$D')" aquameta
	done

	echo "Checking out head commit of every bundle ..."
	sudo -u postgres psql -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" aquameta
else
	for REMOTE in `find $SRC/src/remotes/*.sql -type f`
	do
	    sudo -u postgres psql aquameta -f $REMOTE
	done

	sudo -u postgres psql aquameta -c "select bundle.remote_mount(id) from bundle.remote_database"
	sudo -u postgres psql aquameta -c "select bundle.remote_pull_bundle(r.id, b.id) from bundle.remote_database r, hub.bundle b where b.name != 'org.aquameta.core.bundle'"
	echo "Checking out head commit of every bundle ..."
	sudo -u postgres psql aquameta -c "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;"
fi



#############################################################################
# grant default permissions for 'anonymous' and 'user' roles
#############################################################################

echo ""
echo "New User Registration Scheme"
echo "----------------------------"
echo "Please select a security scheme:"
echo "a) PRIVATE - No anonymous access, no anonymous user registration"
echo "b) OPEN REGISTRATION - Anonymous users may register for an account and read limited data"

REPLY=
until [[ $REPLY =~ ^[AaBb]$ ]]; do
	read -p "Choice? [a/B] " -n 1 -r
    echo
done

sudo -u postgres psql -f $SRC/src/privileges/000-general.sql aquameta

if [[ $REPLY =~ ^[Aa]$ ]]; then
	echo "Installing PRIVATE security scheme..."
	sudo -u postgres psql -f $SRC/src/privileges/001-anonymous.sql aquameta
else if [[ $REPLY =~ ^[Bb]$ ]]; then
        echo "Installing OPEN REGISTRATION scheme..."
        sudo -u postgres psql -f $SRC/src/privileges/001-anonymous-register.sql aquameta
    fi
fi

sudo -u postgres psql -f $SRC/src/privileges/002-user.sql aquameta



#############################################################################
# setup aquameta superuser
#############################################################################

echo "Superuser Registration"
echo "----------------------"
echo "Enter the name, email and password of the user you'd like to setup as superuser:"
read -p "Full Name: " NAME
read -p "Email Address: " EMAIL
read -p "PostgreSQL Username [$(logname)]: " ROLE
if [[ $ROLE = '' ]]
then
	ROLE=$(logname)
fi
read -s -p "Password: " PASSWORD

echo ""
echo "Creating superuser...."
REG_COMMAND="select endpoint.register_superuser('$EMAIL', '$PASSWORD', '$NAME', '$ROLE')"
sudo -u postgres psql -c "$REG_COMMAND" aquameta



#############################################################################
# finished!
#############################################################################
MACHINE_IP=`hostname --ip-address|cut -d ' ' -f1`
# EXTERNAL_IP=`dig +short myip.opendns.com @resolver1.opendns.com`
EXTERNAL_IP=`dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com`

echo ""
echo "Aquameta was successfully installed.  Next, login and configure your installation:"
echo ""
echo "Localhost link: http://localhost/login"
echo "Machine link:   http://$MACHINE_IP/login"
echo "External link:  http://$EXTERNAL_IP/login"

