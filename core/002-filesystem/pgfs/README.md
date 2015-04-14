Install
=======

1. Get FUSE
2. Make sure you're in the FUSE group
3. Install requirements.txt: `pip install -r requirements.txt`

Running
=======

You really only need a database and a mountpoint. For a minimal working thing:

    pgfs.py -d <db> /tmp/mnt


````
usage: postgrefs.py [-h] [--port PORT] [--host HOST] -d DATABASE [-u USERNAME]
                    [-p PASSWORD]
                    mount_point

Mount a PostgreSQL database with FUSE.

positional arguments:
  mount_point

optional arguments:
  -h, --help            show this help message and exit
  --port PORT
  --host HOST
  -d DATABASE, --database DATABASE
  -u USERNAME, --username USERNAME
  -p PASSWORD, --password PASSWORD
````
