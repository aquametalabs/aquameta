Filesystem Foreign Data Wrapper
===============================
Exposes the filesystem to PostgreSQL, allowing files and directories to be read via SQL commands.

Install
-------

First, install the required python modules:

```shell
pip install -r requirements.txt
pip install .
```

Next, install the extension files into PostgreSQL's `extension` directory:
```shell
make install
```

Finally, from a PostgreSQL shell, install the extension:
```sql
CREATE EXTENSION multicorn;
CREATE EXTENSION filesystem_fdw;
```


Usage
-----

### filesystem.file

List files in a directory or show contents of a file

```
-------------------------------------------------------------------------------------------------------------------------------------------
| id                | directory_id | name         | path              | content | permissions | links | size | owner | group | last_mod   |
-------------------------------------------------------------------------------------------------------------------------------------------
| /etc/einstein.jpg | /etc/        | einstein.jpg | /etc/einstein.jpg | ...     | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 |
-------------------------------------------------------------------------------------------------------------------------------------------
```

- ls
```sql
select permissions, links, size, owner, group, last_mod, name from filesystem.file where directory_id = '/var/www/public';
```

- cat
```sql
select content from filesystem.file where path = '/var/www/public/index.php';
```

### filesystem.directory 

List contents of a directory

```
-----------------------------------------------------------------------------------------------------------------------
| id              | parent_id | name   | path               | permissions | links | size | owner | group | last mod   |
-----------------------------------------------------------------------------------------------------------------------
| /var/www/public | /var/www  | public | /var/www/public    | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 |
-----------------------------------------------------------------------------------------------------------------------
```

- ls
```sql
select * from filesystem.directory where parent_id = '/var/www';
```
