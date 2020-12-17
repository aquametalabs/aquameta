# Aquameta Server

The runtime server for Aquameta, providing the following:
- HTTP server
- Embedded PostgreSQL server
- User interface
- Peer-to-peer service

## Installation

1. Edit the `config.toml` configuration file
1. Make all aquameta extensions, and then copy the `xxxxx-0.3.0.sql` and
   `xxxxx.control` files into the `./extension` directory
1. `go build`
1. `./aquameta`

## Generate private key (.key)

If `config.toml` is configured to use the `https` protocol, SSL certificates
   need to be generated. Currently, webview doesn't allow unsigned
   certificates, so probalby just use `http`.

```
openssl genrsa -out server.key 2048
openssl ecparam -genkey -name secp384r1 -out server.key
openssl req -new -x509 -sha256 -key server.key -out server.crt -days 3650
```
