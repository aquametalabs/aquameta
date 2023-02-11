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
    a.Mode = os.ModeDir | 0o400
    return nil
}

func (d Dir) Lookup(ctx context.Context, name string) (fs.Node, error) {
    return SchemaDir{d.fs}, nil
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



// SchemaDir
type SchemaDir struct{
    fs FS
}

func (SchemaDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o400
    return nil
}

func (d SchemaDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
        return TableDir{d.fs}, nil
}

func (d SchemaDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name from meta.relation where schema_name=%s and primary_key_column_ids is not null",
         pq.QuoteLiteral("bundle"))
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






// TableDir
type TableDir struct{
    fs FS
}

func (TableDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o400
    return nil
}

func (d TableDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
        return RowDir{d.fs}, nil
}

func (d TableDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select %s as pk_value from %s.%s",
         pq.QuoteIdentifier("id"),
         pq.QuoteIdentifier("bundle"),
         pq.QuoteIdentifier("commit"))

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






// RowDir
type RowDir struct{
    fs FS
}

func (RowDir) Attr(ctx context.Context, a *fuse.Attr) error {
    a.Inode = 1
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())
    a.Mode = os.ModeDir | 0o400
    return nil
}

func (d RowDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
        return FieldFile{d.fs}, nil
}

func (d RowDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name as column_name from meta.column where schema_name=%s and relation_name=%s",
         pq.QuoteLiteral("bundle"),
         pq.QuoteLiteral("commit"))
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




// File implements both Node and Handle for the hello file.
type FieldFile struct{
    fs FS
}



const greeting = "hello, world\n"

func (ff FieldFile) Attr(ctx context.Context, a *fuse.Attr) error {
    var length int

    q := fmt.Sprintf("select octet_length(%s) as length from %s.%s where %s = %s",
         pq.QuoteIdentifier("message"), // column name
         pq.QuoteIdentifier("bundle"), // bundle_name
         pq.QuoteIdentifier("commit"), // schema_name
         pq.QuoteIdentifier("id"), // pk_column_name
         pq.QuoteLiteral("fdf62c69-544b-4f9a-ab2e-dc5a64cb2d44")) // pk_value

    err := ff.fs.dbpool.QueryRow(context.Background(), q).Scan(&length)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }

    a.Inode = 2
    a.Size = uint64(length)

	// Set owner to current user
    a.Uid = uint32(syscall.Geteuid())
    a.Gid = uint32(syscall.Getegid())

	// Set the file mode to read-only
	a.Mode = a.Mode | syscall.S_IRUSR | syscall.S_IRGRP
	a.Mode = a.Mode &^ (syscall.S_IWUSR | syscall.S_IWGRP)



    return nil
}

func (ff FieldFile) ReadAll(ctx context.Context) ([]byte, error) {
    var content string
    var length int

    q := fmt.Sprintf("select %s as content, octet_length(%s) as length from %s.%s where %s = %s",
         pq.QuoteIdentifier("message"), // column name
         pq.QuoteIdentifier("message"), // column name
         pq.QuoteIdentifier("bundle"), // bundle_name
         pq.QuoteIdentifier("commit"), // schema_name
         pq.QuoteIdentifier("id"), // pk_column_name
         pq.QuoteLiteral("fdf62c69-544b-4f9a-ab2e-dc5a64cb2d44")) // pk_value

    err := ff.fs.dbpool.QueryRow(context.Background(), q).Scan(&content, &length)

    if err != nil {
        log.Fatal("Error querying database: ", err)
    }

    return []byte(greeting), nil
}
