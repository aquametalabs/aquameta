//go:build !(linux || freebsd)
package main

import (
  "github.com/jackc/pgx/v5/pgxpool"
  "log"
)

func pgfs(config tomlConfig, dbpool *pgxpool.Pool, fuseDone chan bool) {
	if config.PGFS.Enabled {
        log.Printf("PGFS Filesystem uses the bazil.org/fuse library which supports Linux and FreeBSD only.\n\n")
    }
}
