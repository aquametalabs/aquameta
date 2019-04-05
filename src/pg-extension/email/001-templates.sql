/******************************************************************************
 * EMAIL
 * Simple templating language - uses python's string.Template lib
 *
 * Copyriright (c) 2019 - Aquameta - http://aquameta.org/
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
