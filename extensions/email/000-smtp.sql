/******************************************************************************
 * EMAIL
 * Send email via external SMTP server
 * Receive??
 * 
 * Created by Aquameta Labs, an open source company in Portland Oregon, USA.
 * Company: http://aquameta.com/
 * Project: http://blog.aquameta.com/
 ******************************************************************************/

/******************************************************************************
 * email.smtp_server
 * An SMTP server configuration, identified by name, and consumed by email.email(name).
 ******************************************************************************/

create table email.smtp_server (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text unique,
    hostname text default 'localhost',
    port integer default 587,
    use_ttls boolean default false,
    ttl_username text,
    ttl_password text
);

insert into email.smtp_server( id, name ) values ('ffb6e431-daa7-4a87-b3c5-1566fe73177c', 'local');

/******************************************************************************
 * email.send
 ******************************************************************************/

create function email.send (
    smtp_server_name text,
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
plan = plpy.prepare("SELECT * FROM email.smtp_server WHERE name = $1", ["text"])
rv = plpy.execute(plan, [smtp_server_name])

if len(rv) != 1:
        plpy.error('No such SMTP server as "%s"' % smtp_server_name)

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
 * email.template
 ******************************************************************************/

create table email.template (
    id uuid not null default public.uuid_generate_v4() primary key,
    subject text not null default '',
    body text not null default ''
);

/******************************************************************************
 * email.template_render( template_id, args json )
 ******************************************************************************/
create function email.template_render(
    template text,
    args public.hstore
) returns void as $$
from string import Template
s = Template(template)
s.substitute(args)
$$ language plpythonu;


/******************************************************************************
 * email.template_send( server, from, to, template_id, template_args )
 ******************************************************************************/

create function email.template_send (
    smtp_server_name text,
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
        smtp_server_name,
        from_email,
        to_email,
        email.template_render( template.subject, template_args ),
        email.template_render( template.body, template_args )
    );
*/
$$ language sql;
