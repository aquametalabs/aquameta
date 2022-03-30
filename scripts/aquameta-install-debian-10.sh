# update and upgrade apt repos
apt -y update && apt -y upgrade
apt -y install gnupg2 wget vim git tmux

# postgresql
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt -y update
apt -y install postgresql-14

# golang
wget https://go.dev/dl/go1.18.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.18.linux-amd64.tar.gz

./make_install_extensions.sh

# path TODO
export PATH=$PATH:/usr/local/go/bin

cd ../
go build

