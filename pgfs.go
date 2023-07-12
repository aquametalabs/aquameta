package main

import "github.com/jackc/pgx/v4/pgxpool"

func pgfs(config tomlConfig, dbpool *pgxpool.Pool, fuseDone chan bool) {}
