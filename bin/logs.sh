tail -f /var/log/postgresql/postgresql-10-main.log /var/log/nginx/aquameta_db.*.log
journalctl -u aquameta.emperor.uwsgi.service -f
