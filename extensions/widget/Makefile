EXTENSION = widget
EXTVERSION = 0.3.0
DATA = $(EXTENSION)--$(EXTVERSION).sql
PG_CONFIG = pg_config

$(EXTENSION)--$(EXTVERSION).sql: $(sort $(filter-out $(wildcard *--*.sql),$(wildcard *.sql)))
	rm -f $@
	cat $^ > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
