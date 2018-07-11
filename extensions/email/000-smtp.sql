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
 * email.email
 ******************************************************************************/

create function email.email (
    stmp_server_name text,
    from_email text,
    to_email text[],
    subject text,
    body text
) returns void as $$

# -- Import smtplib for the actual sending function
import smtplib
from email.mime.text import MIMEText

# -- Create the container (outer) email message.
msg = MIMEText(body)
msg['Subject'] = subject
msg['From'] = from_email
msg['To'] = ', '.join(to_email)

# -- Send the email via our own SMTP server.

# localhost
# s = smtplib.SMTP("localhost")
# s.sendmail(from_email, to_email, msg.as_string())
# s.quit()

# aws ses
# server = smtplib.SMTP('email-smtp.eu-west-1.amazonaws.com', 587)
# server.starttls()
# server.login("USER", "PASS")
# text = msg.as_string()
# server.sendmail(from_address, to_address, text)
# server.quit()

# by arg
plan = plpy.prepare("SELECT * FROM email.smtp_server WHERE name = $1", ["text"])
rv = plpy.execute(plan, ["aws"])
if len(rv) != 1:
    
settings = rv[0]

server = smtplib.SMTP(settings["hostname"], settings["port"])

if settings["use_ttls"] == true:
    server.starttls()
    server.login(settings["ttl_username"], settings["ttl_password"])

text = msg.as_string()
server.sendmail(from_address, to_address, text)
server.quit()


$$ language plpythonu;


create table email.smtp_server (
    id uuid not null default public.uuid_generate_v4() primary key,
    name text not null default '' unique,
    hostname text not null default 'localhost',
    port integer not null default 587,
    use_ttls boolean not null default false,
    ttl_username text not null default '',
    ttl_password text not null default ''
);

