Aquameta Privileges
===================

There are two primary roles in the Aquameta permissions system, `anonymous` and
`user`.  There are two available privileges schemes, one of which is chosen at
installation time:  invite-only and register.

## Invite-Only Scheme ##

This scenario is the most restrictive, and enabled by default.  `anonymous` is
granted usage on a very limited set of rows, only those necessary to display
the login page.

## Register Scheme ##

This scenario the `anonymous` role to register a new user on the system.  The
`anonymous` role is granted access to rows necessary to register, confirm
registration, and login.

Registered users inherit privileges from the `user` role, which gives them
read-only access to the entire database.
