//go:build !(linux || freebsd)
package main

import "github.com/jackc/pgx/v4/pgxpool"

func pgfs(config tomlConfig, dbpool *pgxpool.Pool, fuseDone chan bool) {
	if tomlConfig.PGFS.Enabled {
        log.Printf("PGFS Filesystem uses the bazil.org/fuse library which supports Linux and FreeBSD only.\n\n")
    }
}
