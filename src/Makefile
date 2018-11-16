SHELL=/bin/bash

all:
	@for a in $$(ls); do \
		if [ -d $$a ]; then \
			echo "Building extension $$a..."; \
			$(MAKE) -C $$a; \
		fi; \
	done;
	@echo "Done!"

install:
	@for a in $$(ls); do \
		if [ -d $$a ]; then \
			echo "Installing extension $$a..."; \
			$(MAKE) install -C $$a; \
		fi; \
	done;
	@echo "Done!"
