#!/usr/bin/env bash

# Centralized list of all services in the Privacy Hub stack
export STACK_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion cobalt cobalt-web searxng immich watchtower"

# Services that are built locally from source
export SOURCE_BUILT_SERVICES="hub-api odido-booster scribe dashboard wikiless cobalt-web"

# All container names (without prefix) for cleanup and management
export ALL_CONTAINERS="gluetun adguard dashboard portainer wg-easy hub-api odido-booster redlib wikiless wikiless-redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd cobalt cobalt-web searxng searxng-redis immich-server immich-db immich-redis immich-ml watchtower docker-proxy"

# Infrastructure images that should be pre-pulled
export CRITICAL_IMAGES="nginx:alpine python:3.11-alpine alpine:latest redis:alpine postgres:14-alpine searxng/searxng:latest ghcr.io/imputnet/cobalt:latest ghcr.io/usememos/memos:latest containrrr/watchtower:latest"

# Default tags for specific services
export IMMICH_DEFAULT_TAG="release"

# Service Repository Mapping for dynamic tag resolution
declare -A SERVICE_REPOS
SERVICE_REPOS[wikiless]="https://github.com/Metastem/Wikiless"
SERVICE_REPOS[scribe]="https://git.sr.ht/~edwardloveall/scribe"
SERVICE_REPOS[invidious]="https://github.com/iv-org/invidious.git"
SERVICE_REPOS[odido-booster]="https://github.com/Lyceris-chan/odido-bundle-booster.git"
SERVICE_REPOS[vert]="https://github.com/VERT-sh/VERT.git"
SERVICE_REPOS[vertd]="https://github.com/VERT-sh/vertd.git"
SERVICE_REPOS[rimgo]="https://codeberg.org/rimgo/rimgo.git"
SERVICE_REPOS[breezewiki]="https://github.com/PussTheCat-org/docker-breezewiki-quay.git"
SERVICE_REPOS[anonymousoverflow]="https://github.com/httpjamesm/AnonymousOverflow.git"
SERVICE_REPOS[gluetun]="https://github.com/qdm12/gluetun.git"
SERVICE_REPOS[adguard]="https://github.com/AdguardTeam/AdGuardHome.git"
SERVICE_REPOS[unbound]="https://github.com/klutchell/unbound-docker.git"
SERVICE_REPOS[memos]="https://github.com/usememos/memos.git"
SERVICE_REPOS[redlib]="https://github.com/redlib-org/redlib.git"
SERVICE_REPOS[companion]="https://github.com/iv-org/invidious-companion.git"
SERVICE_REPOS[wg-easy]="https://github.com/wg-easy/wg-easy.git"
SERVICE_REPOS[portainer]="https://github.com/portainer/portainer.git"
SERVICE_REPOS[cobalt]="https://github.com/imputnet/cobalt.git"
export SERVICE_REPOS
