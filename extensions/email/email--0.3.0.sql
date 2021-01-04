/******************************************************************************
 * Email
 * Send email via external SMTP server
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/******************************************************************************
 * email.smtp_server
 * An SMTP server configuration, identified by name, and consumed by email.email(name).
 ******************************************************************************/

create table email.smtp_server (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text unique,
    hostname text default 'localhost',
    port integer default 25,
    use_ttls boolean default false,
    ttl_username text,
    ttl_password text
);

insert into email.smtp_server( id, name ) values ('ffb6e431-daa7-4a87-b3c5-1566fe73177c', 'local');

/******************************************************************************
 * email.send
 ******************************************************************************/

create function email.send (
    smtp_server_id uuid,
    from_email text,
    to_email text[],
    subject text,
    body text
) returns void as $$

import smtplib
from email.mime.text import MIMEText

msg = MIMEText(body)
msg['Subject'] = subject
msg['From'] = from_email
msg['To'] = ', '.join(to_email)

# grab the server settings
plan = plpy.prepare("select * from email.smtp_server where id = $1", ["uuid"])
rv = plpy.execute(plan, [smtp_server_id])

if len(rv) != 1:
        plpy.error('No such SMTP server with id="%s"', smtp_server_id)

settings = rv[0]

server = smtplib.SMTP(settings["hostname"], settings["port"])

if settings["use_ttls"] == True:
        server.starttls()
        server.login(settings["ttl_username"], settings["ttl_password"])

text = msg.as_string()
server.sendmail(from_email, to_email, text)
server.quit()

$$ language plpythonu;
/******************************************************************************
 * EMAIL
 * Simple templating language - uses python's string.Template lib
 *
 * Copyright (c) 2019 - Aquameta - http://aquameta.org/
 ******************************************************************************/

/******************************************************************************
 * email.template
 ******************************************************************************/

create table email.template (
    id uuid not null default public.uuid_generate_v4() primary key,
    subject text not null default '',
    body_text text not null default '',
    body_html text default ''
);

/******************************************************************************
 * email.template_render( template_id, args json )
 ******************************************************************************/
create function email.template_render(
    template text,
    vars public.hstore
) returns text as $$
from string import Template

s = Template(template)

# this is not working
plpy.info(type(vars))
plpy.info(vars)

return s.substitute(vars)
$$ language plpythonu;


/******************************************************************************
 * email.template_send( server, from, to, template_id, template_args )
 ******************************************************************************/

create function email.template_send (
    smtp_server_id uuid,
    from_email text,
    to_email text[],
    template_id uuid,
    template_args json
) returns void as $$
/*
    with template as (
        select subject, body from email.template where id=template_id
    )
    select email.send (
        smtp_server_id,
        from_email,
        to_email,
        email.template_render( template.subject, template_args ),
        email.template_render( template.body, template_args )
    );
*/
$$ language sql;
