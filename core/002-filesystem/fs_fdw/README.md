Filesystem Foreign Data Wrapper
===============================

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

