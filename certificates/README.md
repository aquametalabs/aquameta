# Certificates

Running Aquameta over SSL has some advantages.  Besides encrypted traffic, it
also means that HTTP v2 (H2) is supported.  H2 supports connection keep-alive,
so that multiple requests can use the same TCP/IP connection instead of having
to reconnect for each request.  Since Aquameta is fairly request-heavy, this
can lead to a significant performance increase.

To run Aquameta over SSL, first generate an SSL certificate:

```
openssl genrsa -out server.key 2048
openssl ecparam -genkey -name secp384r1 -out server.key
openssl req -new -x509 -sha256 -key server.key -out server.crt -days 3650
```

Then in your [config file](../conf), change the Protocol setting to `https`, and
reference these generated files.
