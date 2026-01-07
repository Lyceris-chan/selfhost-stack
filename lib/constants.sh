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
export CRITICAL_IMAGES="nginx:alpine python:3.11-alpine node:alpine oven/bun:alpine alpine:latest redis:alpine postgres:14-alpine neilpang/acme.sh:latest"

# Default strategy for source-built services
# Setting these to 'stable' will trigger dynamic tag resolution in zima.sh
export INVIDIOUS_DEFAULT_TAG="stable"
export REDLIB_DEFAULT_TAG="stable"
export WIKILESS_DEFAULT_TAG="stable"
export SCRIBE_DEFAULT_TAG="stable"
export ODIDO_BOOSTER_DEFAULT_TAG="stable"
export VERT_DEFAULT_TAG="stable"
export VERTD_DEFAULT_TAG="nightly"
export RIMGO_DEFAULT_TAG="stable"
export BREEZEWIKI_DEFAULT_TAG="stable"
export ANONYMOUSOVERFLOW_DEFAULT_TAG="stable"
export GLUETUN_DEFAULT_TAG="stable"
export ADGUARD_DEFAULT_TAG="stable"
export UNBOUND_DEFAULT_TAG="stable"
export MEMOS_DEFAULT_TAG="stable"
export PORTAINER_DEFAULT_TAG="stable"
export COMPANION_DEFAULT_TAG="master"
export SEARXNG_DEFAULT_TAG="latest"
export IMMICH_DEFAULT_TAG="release"
export COBALT_DEFAULT_TAG="latest"
