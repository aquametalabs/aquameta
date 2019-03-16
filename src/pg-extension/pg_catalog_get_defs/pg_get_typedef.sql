/*
 * pg_catalog.pg_get_functiondef_no_searchpath(oid)
 *
 * wraps the pg_get_functiondef() function, eliminating the search path so that
 * fully schema-qualified names are used on types, tables, views, etc.
 */

create or replace function pg_catalog.pg_get_functiondef_no_searchpath(oid) returns text
    language plpgsql
    as $$
    declare
        defn text;
    begin
        set local search_path=pg_catalog;
        select into defn pg_catalog.pg_get_functiondef($1);
        return defn;
    end;
    $$;



-- written by RhodiumToad on IRC in one hour :)

create or replace function get_typedef_enum(oid) returns text
  language plpgsql
  as $$
  declare
    defn text;
  begin
	set local search_path=pg_catalog;
    select into defn
           format('CREATE TYPE %s AS ENUM (%s)',
                  $1::regtype,
                  string_agg(quote_literal(enumlabel), ', '
                             order by enumsortorder))
      from pg_enum
     where enumtypid = $1;
    return defn;
  end;
  $$;

create or replace function get_typedef_composite(oid) returns text
  language plpgsql
  as $$
  declare
    defn text;
  begin
	set local search_path=pg_catalog;
    select into defn
           format('CREATE TYPE %s AS (%s)',
                  $1::regtype,
                  string_agg(coldef, ', ' order by attnum))
      from (select a.attnum,
                   format('%I %s%s',
                          a.attname,
                          format_type(a.atttypid, a.atttypmod),
                          case when a.attcollation <> ct.typcollation
                               then format(' COLLATE %I ', co.collname)
                               else ''
                          end) as coldef
              from pg_type t
              join pg_attribute a on a.attrelid=t.typrelid
              join pg_type ct on ct.oid=a.atttypid
              left join pg_collation co on co.oid=a.attcollation
             where t.oid = $1
               and a.attnum > 0
               and not a.attisdropped) s;
    return defn;
  end;
  $$;

create or replace function get_typedef_domain(oid) returns text
  language plpgsql
  as $$
  declare
    defn text;
  begin
	set local search_path=pg_catalog;
    select into defn
           format('CREATE DOMAIN %s AS %s%s%s',
                  $1::regtype,
                  basetype,
                  case when defval is not null then ' ' else '' end,
                  coalesce(defval, ''))
      from (select format_type(t.typbasetype, t.typtypmod) as basetype,
                   pg_get_expr(t.typdefaultbin, 0) as defval
              from pg_type t
             where t.oid = $1) s;
    return defn;
  end;
  $$;

create or replace function get_typedef_range(oid) returns text
  language plpgsql
  as $$
  declare
    defn text;
  begin
	set local search_path=pg_catalog;
    select into defn
           format('CREATE TYPE %s AS RANGE (%s)',
                  $1::regtype,
                  string_agg(format('%s = %s', propname, propval),', '
                             order by keypos)
                    filter (where propval is not null))
      from (select v.keypos, v.propname, v.propval
              from pg_range r
              join pg_type st on st.oid=r.rngsubtype
              join pg_opclass opc on opc.oid=r.rngsubopc
              join pg_namespace n on n.oid=opc.opcnamespace
              left join pg_collation co on co.oid=r.rngcollation
              join lateral (values (1, 'SUBTYPE', format_type(r.rngsubtype, NULL)),
                                   (2, 'SUBTYPE_OPCLASS', case when not opc.opcdefault
                                                               then format('%I.%I',
                                                                           n.nspname,
                                                                           opc.opcname)
                                                          end),
                                   (3, 'COLLATION', case when r.rngcollation <> st.typcollation
                                                         then quote_ident(co.collname)
                                                    end),
                                   (4, 'CANONICAL', nullif(r.rngcanonical::oid,0)::regproc::text),
                                   (5, 'SUBTYPE_DIFF', nullif(r.rngsubdiff::oid,0)::regproc::text))
                             as v(keypos,propname,propval)
                on true
             where r.rngtypid = $1) s;
    return defn;
  end;
  $$;


create or replace function get_typedef_base(oid) returns text
  language plpgsql
  as $$
  declare
    defn text;
  begin
	set local search_path=pg_catalog;
    select into defn
           format('CREATE TYPE %s AS (%s)',
                  $1::regtype,
                  string_agg(format('%s = %s', propname, propval),', '
                             order by keypos)
                    filter (where propval is not null))
      from (select v.keypos, v.propname, v.propval
              from pg_type t
              join lateral
                     (values
                       (1, 'INPUT', t.typinput::text),
                       (2, 'OUTPUT', t.typoutput::text),
                       (3, 'RECEIVE', nullif(t.typreceive,0)::regproc::text),
                       (4, 'SEND', nullif(t.typsend,0)::regproc::text),
                       (5, 'TYPMOD_IN', nullif(t.typmodin,0)::regproc::text),
                       (6, 'TYPMOD_OUT', nullif(t.typmodout,0)::regproc::text),
                       (7, 'ANALYZE', nullif(t.typanalyze,0)::regproc::text),
                       (8, 'INTERNALLENGTH', case when t.typlen = -1
                                                  then 'VARIABLE'
                                                  else t.typlen::text
                                             end),
                       (9, 'PASSEDBYVALUE', nullif(t.typbyval,false)::text),
                       (10, 'ALIGNMENT', case t.typalign
                                         when 'd' then 'double'
                                         when 'i' then 'int4'
                                         when 's' then 'int2'
                                         when 'c' then 'char'
                                         end),
                       (11, 'STORAGE', case t.typstorage
                                       when 'p' then 'plain'
                                       when 'm' then 'main'
                                       when 'e' then 'external'
                                       when 'x' then 'extended'
                                       end),
                       (12, 'CATEGORY', quote_literal(t.typcategory)),
                       (13, 'PREFERRED', nullif(t.typispreferred,false)::text),
                       (14, 'DEFAULT', case when t.typdefaultbin is not null
                                           then pg_get_expr(t.typdefaultbin, 0)
                                      end),
                       (15, 'ELEMENT', nullif(t.typelem,0)::regtype::text),
                       (16, 'DELIMITER', nullif(t.typdelim,',')::text),
                       (17, 'COLLATABLE', case when t.typcollation <> 0 then 'true' end))
                      as v(keypos,propname,propval)
                on true
             where t.oid = $1) s;
    return defn;
  end;
  $$;

create function get_typedef(typid oid) returns text
  language plpgsql
  as $$
  declare
    r record;
  begin
	set local search_path=pg_catalog;
    select into r * from pg_type where oid = typid;
    if not found then
      raise exception 'unknown type oid %', typid;
    end if;
    case r.typtype
      when 'b' then return get_typedef_base(typid);
      when 'd' then return get_typedef_domain(typid);
      when 'c' then return get_typedef_composite(typid);
      when 'e' then return get_typedef_enum(typid);
      when 'r' then return get_typedef_range(typid);
      when 'p' then
        if not r.typisdefined then
          return format('CREATE TYPE %s', typid::regtype);
        end if;
        raise exception 'type % is a pseudotype', typid::regtype;
      else
        raise exception 'type % has unknown typtype %', typid::regtype, r.typtype;
    end case;
  end;
$$;
