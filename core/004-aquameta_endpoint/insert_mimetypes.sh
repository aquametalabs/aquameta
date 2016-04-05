IFS=','
while read -a vals; do
    psql -c "with new_mimetype as ( insert into endpoint.mimetype (mimetype) values ('${vals[1]}') returning id )
        insert into endpoint.mimetype_extension(mimetype_id, extension) values ((select id from new_mimetype), '${vals[0]}');" -U postgres aquameta
done <mimetypes.sql
