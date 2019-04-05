/******************************************************************************
 * Email
 * Send email via external SMTP server
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
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
