Filesystem Foreign Data Wrapper
===============================

Todo
----

- Filesystem.file should only show files?

- Encoding is incorrect for reading files

-- Currently you need to 

```sql
select convert_from(content, 'UTF8') from filesystem.file where id='/s/aquameta/test.sh';
```

Install
-------
```shell
cd src/aquameta/core/002-filesystem/fs_fdw
./install_fs_fdw.sh
psql -U postgres aquameta
```

Spec for fs_fdw.

Mickey Burks <mickey@aquameta.com>

filesystem.file
---------------

```
-------------------------------------------------------------------------------------------------------------------------------------------
| id                | name         | path              | directory_id | permissions | links | size | owner | group | last_mod   | content |
-------------------------------------------------------------------------------------------------------------------------------------------
| /etc/einstein.jpg | einstein.jpg | /etc/einstein.jpg | /etc         | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 | ...     |
-------------------------------------------------------------------------------------------------------------------------------------------
```

- ls
```sql
select permissions, links, size, owner, group, last_mod, name from filesystem.file where path = '/var/www/public';
```

- cat
```sql
select content from filesystem.file where path = '/var/www/public' and name = 'index.php';
```

filesystem.directory 
--------------------

```
-----------------------------------------------------------------------------------------------------------------------
| id              | name   | path               | parent_id | permissions | links | size | owner | group | last mod   |
-----------------------------------------------------------------------------------------------------------------------
| /var/www/public | public | /var/www/public    | /var/www  | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 |
-----------------------------------------------------------------------------------------------------------------------
```

- ls
```sql
select * from filesystem.directory where path = '/var/www';
```

