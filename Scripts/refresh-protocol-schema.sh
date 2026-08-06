#!/bin/sh
set -eu
mkdir -p ProtocolSchemas
codex app-server generate-json-schema --out ProtocolSchemas
