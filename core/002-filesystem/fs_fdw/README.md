Filesystem Foreign Data Wrapper
===============================

Spec for fs_fdw.
Mickey Burks <mickey@aquameta.com>

filesystem.file
---------------

```
| name         | path            | permissions | links | size | owner | group | last mod   | name      | content |
------------------------------------------------------------------------------------------------------------------
| einstein.jpg | /var/www/public | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 | index.php | ...     |
```

- ls
```sql
select * from filesystem.file where path = '/var/www/public';
```

- cat
```sql
select content from filesystem.file where path = '/var/www/public' and name='einstein.jpg';
```

filesystem.directory 
--------------------

```
| path               | permissions | links | size | owner | group | last mod   | name   |
-----------------------------------------------------------------------------------------
| /var/www/public    | drwxr-xr-x  | 1     | 3    | mic   | staff | Dec 1 2015 | public |
```

- ls
```sql
select * from filesystem.directory where path = '/var/www';
```

- mkdir?  do we want to support writable?
```sql
insert into filesystem.directory (path, name) values ('/var/www’, 'public');
```
