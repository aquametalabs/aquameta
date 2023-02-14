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

//
// File System
//


type FS struct{
    dbpool *pgxpool.Pool
}

func (f FS) Root() (fs.Node, error) {
    return Dir{f}, nil
}

//
// Root Directory
//

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
        log.Println("Dir Lookup: Error querying database: ", err)
        return nil, fuse.ENOENT
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
        log.Fatal("Dir ReadDirAll: Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var name string

        err := rows.Scan(&name)
        if err != nil {
            log.Fatal("Dir ReadDirAll: Error scanning row", err)
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
        log.Fatal("Dir ReadDirAll: Error iterating rows", rows.Err())
    }

    return append(dirDirs,
        fuse.Dirent{Name: ".", Type: fuse.DT_Dir},
        fuse.Dirent{Name: "..", Type: fuse.DT_Dir}), nil
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
    var exists bool
    var pk_column_name string

    pkQ := fmt.Sprintf("select (primary_key_column_ids[1]).name as pk_column_name from meta.relation where schema_name=%s and name=%s and primary_key_column_ids is not null",
        pq.QuoteLiteral(d.schema_name),
        pq.QuoteLiteral(name))

    // check that relation exists
    existsQ := fmt.Sprintf("select exists(%s)", pkQ)
    err := d.fs.dbpool.QueryRow(context.Background(), existsQ).Scan(&exists)
    if err != nil {
        log.Fatal("Error in SchemaDir Lookup exists: ", err)
        return nil, fuse.ENOENT
    }

    if !exists {
        return nil, fuse.ENOENT
    }

    // get its primary key, for use as variable in TableDir struct
    err = d.fs.dbpool.QueryRow(context.Background(), pkQ).Scan(&pk_column_name)
    if err != nil {
        log.Fatal("Error in SchemaDir Lookup pk query: ", err)
        return nil, fuse.ENOENT
    }
    return TableDir{d.fs, d.schema_name, name, pk_column_name}, nil
}

func (d SchemaDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name from meta.relation where schema_name=%s and primary_key_column_ids is not null",
         pq.QuoteLiteral(d.schema_name))
    rows, err := d.fs.dbpool.Query(context.Background(), q)

    if err != nil {
        log.Fatal("SchemaDir ReadDirAll(): Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var name string

        err := rows.Scan(&name)
        if err != nil {
            log.Fatal("SchemaDir ReadDirAll(): Error scanning row", err)
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
        log.Fatal("SchemaDir ReadDirAll(): Error iterating rows", rows.Err())
    }

    return append(dirDirs,
        fuse.Dirent{Name: ".", Type: fuse.DT_Dir},
        fuse.Dirent{Name: "..", Type: fuse.DT_Dir}), nil
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
    q := fmt.Sprintf("select exists(select 1 from %s.%s where %s::text=%s)",
        pq.QuoteIdentifier(d.schema_name),
        pq.QuoteIdentifier(d.table_name),
        pq.QuoteIdentifier(d.pk_column_name),
        pq.QuoteLiteral(name))
    err := d.fs.dbpool.QueryRow(context.Background(), q).Scan(&exists)
    if err != nil {
        log.Println("TableDir Lookup(): Error querying database: ", err)
        return nil, fuse.ENOENT
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
        log.Fatal("TableDir ReadDirAll(): Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var pk_value string

        err := rows.Scan(&pk_value)
        if err != nil {
            log.Fatal("TableDir ReadDirAll(): Error scanning row", err)
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
        log.Fatal("TableDir ReadDirAll(): Error iterating rows", rows.Err())
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

/*
func (d RowDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
        return FieldFile{d.fs, d.schema_name, d.table_name, name, d.pk_column_name, d.pk_value}, nil
}
*/
func (d RowDir) Lookup(ctx context.Context, name string) (fs.Node, error) {
    // log.Println("RowDir Lookup(): name=", name)
    var columnExists bool
    var rowExists bool

    // check that this column exists (we could probably make this a lot faster by sending garbage queries to the db)
    existsQ := fmt.Sprintf("select exists(select 1 from meta.relation_column where schema_name=%s and relation_name=%s and name=%s)",
        pq.QuoteLiteral(d.schema_name),
        pq.QuoteLiteral(d.table_name),
        pq.QuoteLiteral(name))
    // log.Println("existsQ", existsQ)

    err := d.fs.dbpool.QueryRow(context.Background(), existsQ).Scan(&columnExists)
    if err != nil {
        log.Fatal("RowDir Lookup(): Error in column exists check: ", err)
    }
    if !columnExists {
        return nil, fuse.ENOENT
    }

    // check that row exists
    q := fmt.Sprintf("select exists(select %s from %s.%s where %s::text=%s)",
        pq.QuoteIdentifier(name),
        pq.QuoteIdentifier(d.schema_name),
        pq.QuoteIdentifier(d.table_name),
        pq.QuoteIdentifier(d.pk_column_name),
        pq.QuoteLiteral(d.pk_value))
    err = d.fs.dbpool.QueryRow(context.Background(), q).Scan(&rowExists)
    if err != nil {
        log.Fatal("RowDir Lookup(): Error in row exists check: ", err)
    }
    if !rowExists {
        return nil, fuse.ENOENT
    }

    f := FieldFile{
        fs: d.fs,
        schema_name: d.schema_name,
        table_name: d.table_name,
        column_name: name,
        pk_column_name: d.pk_column_name,
        pk_value: d.pk_value,
    }
    return f, nil;
    // was: return FieldFile{d.fs, d.schema_name, d.table_name, name, d.pk_column_name, d.pk_value}, nil
}


func (d RowDir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
     q := fmt.Sprintf("select name as column_name from meta.column where schema_name=%s and relation_name=%s",
         pq.QuoteLiteral(d.schema_name),
         pq.QuoteLiteral(d.table_name))
    rows, err := d.fs.dbpool.Query(context.Background(), q)

    if err != nil {
        log.Fatal("RowDir ReadDirAll(): Error querying database: ", err)
    }
    defer rows.Close()

    var dirDirs []fuse.Dirent
    for rows.Next() {
        var column_name string

        err := rows.Scan(&column_name)
        if err != nil {
            log.Fatal("RowDir ReadDirAll(): Error scanning row: ", err)
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
        log.Fatal("RowDir ReadDirAll(): Error iterating rows", rows.Err())
    }

    return append(dirDirs,
        fuse.Dirent{Name: ".", Type: fuse.DT_Dir},
        fuse.Dirent{Name: "..", Type: fuse.DT_Dir}), nil
}


//
// FieldFile
//
var fileBuffers = make(map[string]string)

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

    q := fmt.Sprintf("select coalesce(octet_length(%s::text)::integer, 0) as octet_length from %s.%s where %s = %s",
         pq.QuoteIdentifier(ff.column_name),
         pq.QuoteIdentifier(ff.schema_name),
         pq.QuoteIdentifier(ff.table_name),
         pq.QuoteIdentifier(ff.pk_column_name),
         pq.QuoteLiteral(ff.pk_value))

    // fmt.Println(q)

    err := ff.fs.dbpool.QueryRow(context.Background(), q).Scan(&octet_length)

    if err != nil {
        log.Fatal("FileField Attr(): Error querying database: ", err)
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
        log.Fatal("FileField ReadDirAll(): Error querying database: ", err)
    }

    return []byte(content), nil
}


func (ff FieldFile) Write(ctx context.Context, req *fuse.WriteRequest, resp *fuse.WriteResponse) error {
    /*
    log.Printf("######## FieldFile Write():\n    req.Offset: %d\n    req.Data: %s...",
        req.Offset, req.Data[0:19])
    log.Printf("         fileBuffers[%s] %s", key, fileBuffers[key]);
    */

    var key = ff.schema_name+"/"+ff.table_name+"/"+ff.pk_value+"/"+ff.column_name
    fileBuffers[key] = fileBuffers[key] + string(req.Data)

    resp.Size = len(req.Data)
	return nil
}


func (ff FieldFile) Fsync(ctx context.Context, req *fuse.FsyncRequest) error {
    var key = ff.schema_name+"/"+ff.table_name+"/"+ff.pk_value+"/"+ff.column_name

    // log.Printf("!!!!!!!! Fsync called:\n    fileBuffers[%s] %s", key, fileBuffers[key]);

    q := fmt.Sprintf("update %s.%s set %s = %s where %s = %s",
         pq.QuoteIdentifier(ff.schema_name),
         pq.QuoteIdentifier(ff.table_name),
         pq.QuoteIdentifier(ff.column_name),
         pq.QuoteLiteral(fileBuffers[key]),
         pq.QuoteIdentifier(ff.pk_column_name),
         pq.QuoteLiteral(ff.pk_value))
    _, err := ff.fs.dbpool.Exec(context.Background(), q)

    // log.Println("Fsync field update q: ",q)
    if err != nil {
        // Handle error
        log.Printf("FieldFile Flush(): update stmt failed. ",q,err)
    }
    fileBuffers[key] = ""

    return nil
}


func (ff FieldFile) Flush(ctx context.Context, req *fuse.WriteRequest, resp *fuse.WriteResponse) error {
    log.Fatal("######## Flush() called and we don't know what this does.")

/*
    fs.mu.Lock()
    defer fs.mu.Unlock()

    q := fmt.sprintf("update %s.%s set %s = %s where %s = %s",
         pq.quoteidentifier(ff.schema_name),
         pq.quoteidentifier(ff.table_name),
         pq.quoteidentifier(ff.column_name),
         pq.quoteliteral(string(req.data)),
         pq.quoteidentifier(ff.pk_column_name),
         pq.quoteliteral(ff.pk_value))
    _, err := ff.fs.dbpool.exec(context.background(), q)
    if err != nil {
        // handle error
        log.printf("fieldfile flush(): update stmt failed. ",q,err)
    }
*/

    return nil
}
