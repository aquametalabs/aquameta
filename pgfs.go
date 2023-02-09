package main

import (
    "context"
    "log"
    "os"
    "syscall"

    "github.com/jackc/pgx/v4/pgxpool"
    // "github.com/jackc/pgx/v4"
    // "github.com/lib/pq"

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
	a.Mode = os.ModeDir | 0o555
	return nil
}

func (Dir) Lookup(ctx context.Context, name string) (fs.Node, error) {
	if name == "hello" {
		return File{}, nil
	}
	return nil, syscall.ENOENT
}

/*
var dirDirs = []fuse.Dirent{
	{Inode: 2, Name: "hello", Type: fuse.DT_File},
}
*/

func (d Dir) ReadDirAll(ctx context.Context) ([]fuse.Dirent, error) {
    rows, err := d.fs.dbpool.Query(context.Background(), "select name from meta.schema")
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

		log.Println("Schema:", name)
		dirDirs = append(dirDirs, fuse.Dirent{
			Inode: 2,
			Name: name,
			Type: fuse.DT_File,
		})
	}

	if rows.Err() != nil {
		log.Fatal("Error iterating rows", rows.Err())
	}

	return dirDirs, nil
}

// File implements both Node and Handle for the hello file.
type File struct{}

const greeting = "hello, world\n"

func (File) Attr(ctx context.Context, a *fuse.Attr) error {
	a.Inode = 2
	a.Mode = 0o444
	a.Size = uint64(len(greeting))
	return nil
}

func (File) ReadAll(ctx context.Context) ([]byte, error) {
	return []byte(greeting), nil
}
