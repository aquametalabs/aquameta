pg_dump -U postgres -O --schema bundle -a --disable-triggers \
	--exclude-table=tracked_row_added \
	--exclude-table=stage_row_added \
	--exclude-table=stage_row_deleted \
	--exclude-table=stage_field_changed \
aquameta
