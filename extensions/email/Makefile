EXTENSION = email
EXTVERSION = 0.1.0
DATA = email--0.1.0.sql
PG_CONFIG = pg_config

$(EXTENSION)--$(EXTVERSION).sql: $(filter-out $(wildcard *--*.sql),$(wildcard *.sql))
# DATA = $(filter-out $(wildcard sql/*--*.sql),$(wildcard sql/*.sql))

	cat $^ > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
