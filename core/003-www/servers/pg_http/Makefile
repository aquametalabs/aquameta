DATA = pg_http--0.1.sql

EXTENSION = pg_http
EXTVERSION  = $(shell grep default_version $(EXTENSION).control | \
                      sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

MODULE_big = pg_http
OBJS = pg_http.o
PG_CONFIG = pg_config
SHLIB_LINK = -lwebsockets -lpq

PG_CPPFLAGS = -I/usr/include/postgresql

PG93 = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0 | 9\.1| 9\.2" && echo no || echo yes)
ifeq ($(PG93),no)
    $(error Requires PostgreSQL 9.3 or later)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
