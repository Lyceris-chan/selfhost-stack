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
export CRITICAL_IMAGES="nginx:1.27.3-alpine python:3.11.11-alpine3.21 node:20.18.1-alpine3.21 oven/bun:1.1.34-alpine alpine:3.21.0 redis:7.2.6-alpine postgres:14.15-alpine3.21 neilpang/acme.sh:latest"
