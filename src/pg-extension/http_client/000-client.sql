/******************************************************************************
 * WWW - client
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
 *****************************************************************************/

begin;

-- create language plpythonu;
create schema http_client;
set search_path=http_client;



/*******************************************************************************
*
*
* UTILS
* General purpose http client utilities.
*
*
*******************************************************************************/


/*******************************************************************************
* urlencode
* via http://stackoverflow.com/questions/10318014/javascript-encodeuri-like-function-in-postgresql
*******************************************************************************/
CREATE OR REPLACE FUNCTION http_client.urlencode(in_str text, OUT _result text)
    STRICT IMMUTABLE AS $urlencode$
DECLARE
    _i      int4;
    _temp   varchar;
    _ascii  int4;
BEGIN
    _result = '';
    FOR _i IN 1 .. length(in_str) LOOP
        _temp := substr(in_str, _i, 1);
        IF _temp ~ '[0-9a-zA-Z:/@._?#-]+' THEN
            _result := _result || _temp;
        ELSE
            _ascii := ascii(_temp);
            IF _ascii > x'07ff'::int4 THEN
                RAISE EXCEPTION 'Won''t deal with 3 (or more) byte sequences.';
            END IF;
            IF _ascii <= x'07f'::int4 THEN
                _temp := '%'||to_hex(_ascii);
            ELSE
                _temp := '%'||to_hex((_ascii & x'03f'::int4)+x'80'::int4);
                _ascii := _ascii >> 6;
                _temp := '%'||to_hex((_ascii & x'01f'::int4)+x'c0'::int4)
                            ||_temp;
            END IF;
            _result := _result || upper(_temp);
        END IF;
    END LOOP;
    RETURN ;
END;
$urlencode$ LANGUAGE plpgsql;



/*******************************************************************************
* array_to_querystring(args, vals)
* converts an array of args and an array of values to a query_string suitbale for a URL
*******************************************************************************/
create or replace function http_client.array_to_querystring(args text[] default '{}', vals text[] default '{}', out querystring text) as $$
begin
    querystring := '';

    -- array_length called on an empty array returns null
    if args is null or array_length(args,1) is null or vals is null or array_length(vals,1) is null
        then return;
    end if;

    -- raise notice 'qs: %', querystring;
    for i in 1..array_length(args,1) loop
        querystring := querystring
            || http_client.urlencode(args[i])
            -- || args[i]
            || '='
            || http_client.urlencode(vals[i])
            -- || vals[i]
            || '&';
        -- raise notice 'qs: %', querystring;
    end loop;

end;
$$ language plpgsql;



/*******************************************************************************
*
*
* HTTP CLIENT
* Performs GET, POST, DELETE, PATCH operations over HTTP using python's liburl2
*
*
*******************************************************************************/


create type http_client.http_response as (status_code integer, headers text, encoding text, response_text text);
create type http_client.http_response_binary as (status_code integer, headers text, encoding text, response_binary bytea);


/*******************************************************************************
* http_get
*******************************************************************************/
create or replace function http_client.http_get (url text) returns http_client.http_response
as $$

import requests
import plpy

plpy.info ('************ http_get('+url+')')
r = requests.get(url)
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;

/*******************************************************************************
* http_get_binary
*******************************************************************************/
create or replace function http_client.http_get_binary (url text) returns http_client.http_response_binary
as $$

import requests
import plpy

plpy.info ('************ http_get('+url+')')
r = requests.get(url)
return [r.status_code, r.headers, r.encoding, r.content]

$$ language plpythonu;

/*******************************************************************************
* http_post text
*******************************************************************************/
create or replace function http_client.http_post (url text, data text) returns http_client.http_response
as $$
import requests
import plpy

plpy.info ('************ http_post('+url+')')
r = requests.post(url,data)
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;

/*******************************************************************************
* http_post json
*******************************************************************************/
create or replace function http_client.http_post (url text, data json) returns http_client.http_response
as $$
import requests
import plpy
import json

plpy.info ('************ http_post('+url+')')
r = requests.post(url,json.loads(data))
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;

/*******************************************************************************
* http_delete
*******************************************************************************/
create or replace function http_client.http_delete (url text) returns http_client.http_response
as $$

import requests
import plpy

plpy.info ('************ http_delete('+url+')')
r = requests.delete(url)
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;

/*******************************************************************************
* http_patch text
*******************************************************************************/
create or replace function http_client.http_patch (url text, data text) returns http_client.http_response
as $$
import requests
import plpy

plpy.info ('************ http_patch('+url+')')
r = requests.patch(url,data)
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;


/*******************************************************************************
* http_patch json
*******************************************************************************/
create or replace function http_client.http_patch (url text, data json) returns http_client.http_response
as $$
import requests
import plpy
import json

plpy.info ('************ http_patch('+url+')')
r = requests.patch(url,json.loads(data))
return [r.status_code, r.headers, r.encoding, r.text]

$$ language plpythonu;

commit;
