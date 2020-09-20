# Aquameta Server

The web server for Aquameta, implemented in Go.

## Installation

### 1. Build the server by running `go build`
### 2. Install PostgreSQL
### 3. Install the Aquameta extensions
### 4. Generate SSL certificate

Generate private key (.key)

```
openssl genrsa -out server.key 2048
openssl ecparam -genkey -name secp384r1 -out server.key
openssl req -new -x509 -sha256 -key server.key -out server.crt -days 3650
```

### 4. Edit the `config.toml`
### 5. Initialize the database with `aquameta init`
### 6. Start the server with `go run`
