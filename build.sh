#!/bin/bash
if [ ! -d "bin/" ]; then
    mkdir bin
fi

dub build -c web
dub build -c api
dub build -c orchestrator

if [ ! -d "bin/public" ]; then
    cp -R web/public bin/
fi

