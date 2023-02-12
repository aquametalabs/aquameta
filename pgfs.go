package main

import (
    "context"
    "log"
    "os"
    "fmt"
    "syscall"

    "github.com/jackc/pgx/v4/pgxpool"
    // "github.com/jackc/pgx/v4"
    "github.com/lib/pq"

    "bazil.org/fuse"
    "bazil.org/fuse/fs"
)

// FS implements the hello world file system.
type FS struct{
    dbpool *pgxpool.Pool
}

func (f FS) Root() (fs.Node, error) {
    return Dir{f}, nil
}


// Dir implements both Node and Handle for the root directory.
type Dir struct{
    fs FS
}

func (Dir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o500
    return nil
}

func (d Dir) Lookup(ctx context.Context, name string) (fs.Node, error) {
    var exists bool
    q := fmt.Sprintf("select exists(select 1 from meta.schema where name=%s)", pq.QuoteLiteral(name))
    err := d.fs.dbpool.QueryRow(context.Background(), q).Scan(&exists)
    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    if exists {
        return SchemaDir{d.fs, name}, nil
    }
    return nil, fuse.ENOENT

}

func (d Dir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
    q := fmt.Sprintf("select name from meta.schema")
    rows, err := d.fs.dbpool.Query(context.Background(), q)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var name string

        err := rows.Scan(&name)
        if err != nil {
            log.Fatal("Error scanning row", err)
            continue
        }

        // log.Println("Schema:", name)
        dirDirs = append(dirDirs, fuse.Dirent{
            Inode: 2,
            Name: name,
            Type: fuse.DT_Dir,
        })
    }

    if rows.Err() != nil {
        log.Fatal("Error iterating rows", rows.Err())
    }

    return dirDirs, nil
}


//
// SchemaDir
//

type SchemaDir struct{
    fs FS
    schema_name string
}

func (d SchemaDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o500
    return nil
}

func (d SchemaDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
    var pk_column_name string
    q := fmt.Sprintf("select (primary_key_column_ids[1]).name as pk_column_name from meta.relation where schema_name=%s and name=%s and primary_key_column_ids is not null",
		pq.QuoteLiteral(d.schema_name),
		pq.QuoteLiteral(name))

    err := d.fs.dbpool.QueryRow(context.Background(), q).Scan(&pk_column_name)
    if err != nil {
        log.Fatal("Error in SchemaDir Lookup: ", err)
    }

    if pk_column_name != "" {
        return TableDir{d.fs, d.schema_name, name, pk_column_name}, nil
    } else {
        return nil, fuse.ENOENT
    }
}

func (d SchemaDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name from meta.relation where schema_name=%s and primary_key_column_ids is not null",
         pq.QuoteLiteral(d.schema_name))
    rows, err := d.fs.dbpool.Query(context.Background(), q)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var name string

        err := rows.Scan(&name)
        if err != nil {
            log.Fatal("Error scanning row", err)
            continue
        }

        // log.Println("Relation: ", name)
        dirDirs = append(dirDirs, fuse.Dirent{
            Inode: 2,
            Name: name,
            Type: fuse.DT_Dir,
        })
    }

    if rows.Err() != nil {
        log.Fatal("Error iterating rows", rows.Err())
    }

    return dirDirs, nil
}


//
// TableDir
//

type TableDir struct{
    fs FS
    schema_name string
    table_name string
    pk_column_name string
}

func (TableDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o500
    return nil
}

func (d TableDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
    var exists bool
    q := fmt.Sprintf("select exists(select 1 from %s.%s where %s=%s)",
        pq.QuoteIdentifier(d.schema_name),
        pq.QuoteIdentifier(d.table_name),
        pq.QuoteIdentifier(d.pk_column_name),
        pq.QuoteLiteral(name))
    err := d.fs.dbpool.QueryRow(context.Background(), q).Scan(&exists)
    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    if exists {
        return RowDir{d.fs, d.schema_name, d.table_name, d.pk_column_name, name}, nil
    }
    return nil, fuse.ENOENT
}

func (d TableDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select %s as pk_value from %s.%s",
         pq.QuoteIdentifier(d.pk_column_name),
         pq.QuoteIdentifier(d.schema_name),
         pq.QuoteIdentifier(d.table_name))

    rows, err := d.fs.dbpool.Query(context.Background(), q)
    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var pk_value string

        err := rows.Scan(&pk_value)
        if err != nil {
            log.Fatal("Error scanning row", err)
            continue
        }

        // log.Println("Primary Key:", pk_value)
        dirDirs = append(dirDirs, fuse.Dirent{
            Inode: 2,
            Name: pk_value,
            Type: fuse.DT_Dir,
        })
    }

    if rows.Err() != nil {
        log.Fatal("Error iterating rows", rows.Err())
    }

    return dirDirs, nil
}




//
// RowDir
//

type RowDir struct{
    fs FS
    schema_name string
    table_name string
    pk_column_name string
    pk_value string
}

func (RowDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o500
    return nil
}

func (d RowDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
        return FieldFile{d.fs, d.schema_name, d.table_name, name, d.pk_column_name, d.pk_value}, nil
}

func (d RowDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name as column_name from meta.column where schema_name=%s and relation_name=%s",
         pq.QuoteLiteral(d.schema_name),
         pq.QuoteLiteral(d.table_name))
    rows, err := d.fs.dbpool.Query(context.Background(), q)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var column_name string

        err := rows.Scan(&column_name)
        if err != nil {
            log.Fatal("Error scanning row", err)
            continue
        }

        // log.Println("Schema:", column_name)
        dirDirs = append(dirDirs, fuse.Dirent{
            Inode: 2,
            Name: column_name,
            Type: fuse.DT_File,
        })
    }

    if rows.Err() != nil {
        log.Fatal("Error iterating rows", rows.Err())
    }

    return dirDirs, nil
}


//
// FieldFile
//

type FieldFile struct{
    fs FS
    schema_name string
    table_name string
    column_name string
    pk_column_name string
    pk_value string
}


func (ff FieldFile) Attr(ctx context.Context, a *fuse.Attr) error {
    var octet_length int

    q := fmt.Sprintf("select octet_length(%s::text)::integer as octet_length from %s.%s where %s = %s",
         pq.QuoteIdentifier(ff.column_name),
         pq.QuoteIdentifier(ff.schema_name),
         pq.QuoteIdentifier(ff.table_name),
         pq.QuoteIdentifier(ff.pk_column_name),
         pq.QuoteLiteral(ff.pk_value))

    // fmt.Println(q)

    err := ff.fs.dbpool.QueryRow(context.Background(), q).Scan(&octet_length)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }

    a.Inode = 2
    a.Size = uint64(octet_length)
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = 0o644

    return nil
}

func (ff FieldFile) ReadAll(ctx context.Context) ([]byte, error) {
    var content string

    q := fmt.Sprintf("select %s::text as content from %s.%s where %s = %s",
         pq.QuoteIdentifier(ff.column_name),
         pq.QuoteIdentifier(ff.schema_name),
         pq.QuoteIdentifier(ff.table_name),
         pq.QuoteIdentifier(ff.pk_column_name),
         pq.QuoteLiteral(ff.pk_value))

    err := ff.fs.dbpool.QueryRow(context.Background(), q).Scan(&content)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }

    return []byte(content), nil
}
