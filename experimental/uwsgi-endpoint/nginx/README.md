Endpoint nginx Configuration Files
----------------------------------
By default, nginx is configured without SSL encryption.


= Development SSL Configuration
To setup a development SSL server, follow [these instructions](https://www.humankode.com/ssl/create-a-selfsigned-certificate-for-nginx-in-5-minutes).


= Production SSL Configuration
To setup a "real" SSL server with letsencrypt, do something like:
```
sudo apt-get install certbot
sudo certbot --certonly
```

Then copy the `aquameta_endpoint.letsencrypt.conf` file to `/etc/nginx/aquameta_endpoint.conf`.
