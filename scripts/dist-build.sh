#!/bin/bash

xgo -out ./build/spa_desktop --branch=main --targets=linux/amd64,darwin/amd64                   github.com/aquametalabs/aquameta
xgo -out ./build/spa_desktop --branch=main --targets=windows-10/amd64  -ldflags="-H windowsgui" github.com/aquametalabs/aquameta

