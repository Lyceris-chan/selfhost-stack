#!/usr/bin/env bash

# Centralized list of all services in the Privacy Hub stack
export STACK_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion cobalt searxng immich watchtower"

# Services that are built locally from source
export SOURCE_BUILT_SERVICES="hub-api odido-booster scribe dashboard wikiless"

# All container names (without prefix) for cleanup and management
export ALL_CONTAINERS="gluetun adguard dashboard portainer wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd cobalt searxng immich-server immich-db immich-redis immich-machine-learning watchtower"

# Infrastructure images that should be pre-pulled
export CRITICAL_IMAGES="nginx:alpine python:3.11-alpine alpine:latest redis:alpine postgres:14-alpine searxng/searxng:latest ghcr.io/imputnet/cobalt:latest ghcr.io/usememos/memos:latest containrrr/watchtower:latest"

# Default tags for specific services
export IMMICH_DEFAULT_TAG="release"
