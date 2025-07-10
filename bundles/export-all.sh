#!/bin/bash

database_name=$1
if [ -z "$database_name" ]; then
  echo "usage: $0 <database_name>"
  exit 1
fi

../extensions/pg_bundle/export.sh org.aquameta.core.bootloader $database_name > org.aquameta.core.bootloader.json
../extensions/pg_bundle/export.sh org.aquameta.core.endpoint   $database_name > org.aquameta.core.endpoint.json
../extensions/pg_bundle/export.sh org.aquameta.core.ide        $database_name > org.aquameta.core.ide.json
../extensions/pg_bundle/export.sh org.aquameta.core.mimetypes  $database_name > org.aquameta.core.mimetypes.json
../extensions/pg_bundle/export.sh org.aquameta.core.semantics  $database_name > org.aquameta.core.semantics.json
../extensions/pg_bundle/export.sh org.aquameta.core.widget     $database_name > org.aquameta.core.widget.json
../extensions/pg_bundle/export.sh org.aquameta.games.snake     $database_name > org.aquameta.games.snake.json
../extensions/pg_bundle/export.sh org.aquameta.ui.fsm          $database_name > org.aquameta.ui.fsm.json
../extensions/pg_bundle/export.sh org.aquameta.ui.layout       $database_name > org.aquameta.ui.layout.json
../extensions/pg_bundle/export.sh org.aquameta.ui.tags         $database_name > org.aquameta.ui.tags.json
