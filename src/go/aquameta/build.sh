#!/bin/bash

xgo -out ./build/spa_desktop --branch=feature/go_experiments --targets=linux/amd64,darwin/amd64                   github.com/aquametalabs/aquameta/src/go/aquameta
xgo -out ./build/spa_desktop --branch=feature/go_experiments --targets=windows-10/amd64  -ldflags="-H windowsgui" github.com/aquametalabs/aquameta/src/go/aquameta

