#!/usr/bin/env bash

set -e

COMMAND=$1

shift

set -x

for file in **/Tests; do
	swift $COMMAND $@ --package-path "$(dirname "$file")";
done
