module github.com/aquametalabs/aquameta/src/go/aquameta

go 1.15

replace github.com/aquametalabs/embedded-postgres => /home/eric/dev/embedded-postgres

require (
	github.com/BurntSushi/toml v0.3.1
	github.com/aquametalabs/embedded-postgres v1.3.0
	github.com/jackc/pgx/v4 v4.10.0
	github.com/lib/pq v1.9.0
)
