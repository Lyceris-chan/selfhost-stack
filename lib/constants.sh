#!/usr/bin/env bash

# Centralized list of all services in the Privacy Hub stack
# This ensures consistency across deployment, cleanup, and update logic.

# Services that participate in the A/B (blue/green) deployment scheme
export AB_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion cobalt searxng immich"

# Services that require Dockerfile patching
export PATCHABLE_SERVICES="wikiless scribe invidious odido-booster vert rimgo anonymousoverflow gluetun adguard unbound memos redlib wg-easy portainer dashboard"

# All container names (without prefix) for cleanup and management
export ALL_CONTAINERS="gluetun adguard dashboard portainer wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd cobalt searxng immich-server immich-db immich-redis immich-machine-learning"

# Infrastructure images that should be pre-pulled
export CRITICAL_IMAGES="nginx:1.27-alpine python:3.11-alpine node:20-alpine oven/bun:1.1-alpine alpine:3.21 redis:7.2-alpine postgres:14-alpine neilpang/acme.sh:latest ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0 docker.io/valkey/valkey:9"

# Known good versions for source-built services (pinned to prevent upstream breakage)
# Users can override these by setting <SERVICE>_IMAGE_TAG in .env
export INVIDIOUS_DEFAULT_TAG="v2.20250913.0"
export REDLIB_DEFAULT_TAG="v0.35.1"
export WIKILESS_DEFAULT_TAG="main"
export SCRIBE_DEFAULT_TAG="main"
export ODIDO_BOOSTER_DEFAULT_TAG="main"
export VERT_DEFAULT_TAG="main"
export RIMGO_DEFAULT_TAG="main"
export BREEZEWIKI_DEFAULT_TAG="master"
export ANONYMOUSOVERFLOW_DEFAULT_TAG="release"
export GLUETUN_DEFAULT_TAG="v3.40.0"
export ADGUARD_DEFAULT_TAG="master"
export UNBOUND_DEFAULT_TAG="main"
export MEMOS_DEFAULT_TAG="main"
export PORTAINER_DEFAULT_TAG="2.26.1-alpine"
export COMPANION_DEFAULT_TAG="master"
export SEARXNG_DEFAULT_TAG="latest"
export IMMICH_DEFAULT_TAG="release"
export IMMICH_POSTGRES_IMAGE="ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"
export IMMICH_VALKEY_IMAGE="docker.io/valkey/valkey:9"
export COBALT_DEFAULT_TAG="latest"
