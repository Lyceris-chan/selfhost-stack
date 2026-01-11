#!/usr/bin/env bash

# Centralized list of all services in the Privacy Hub stack
export STACK_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion cobalt cobalt-web searxng immich watchtower"

# Services that are built locally from source
export SOURCE_BUILT_SERVICES="hub-api odido-booster scribe dashboard wikiless cobalt-web"

# All container names (without prefix) for cleanup and management
export ALL_CONTAINERS="gluetun adguard dashboard portainer wg-easy api odido-booster redlib wikiless wikiless-redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd cobalt cobalt-web searxng searxng-redis immich-server immich-db immich-redis immich-ml watchtower docker-proxy"

# Infrastructure images that should be pre-pulled
export CRITICAL_IMAGES="nginx:alpine python:3.11-alpine alpine:latest redis:alpine postgres:14-alpine searxng/searxng:latest ghcr.io/imputnet/cobalt:latest ghcr.io/usememos/memos:latest containrrr/watchtower:latest"

# Default tags for specific services
export IMMICH_DEFAULT_TAG="release"

# Port Definitions
export PORT_DASHBOARD_WEB=8081
export PORT_ADGUARD_WEB=8083
export PORT_PORTAINER=9000
export PORT_WG_WEB=51821
export PORT_INVIDIOUS=3000
export PORT_REDLIB=8080
export PORT_WIKILESS=8180
export PORT_RIMGO=3002
export PORT_BREEZEWIKI=8380
export PORT_ANONYMOUS=8480
export PORT_SCRIBE=8280
export PORT_MEMOS=5230
export PORT_VERT=5555
export PORT_VERTD=24153
export PORT_COMPANION=8282
export PORT_COBALT=9001
export PORT_COBALT_API=9002
export PORT_SEARXNG=8082
export PORT_IMMICH=2283

# Internal Ports
export PORT_INT_REDLIB=8081
export PORT_INT_WIKILESS=8180
export PORT_INT_INVIDIOUS=3000
export PORT_INT_RIMGO=3002
export PORT_INT_BREEZEWIKI=10416
export PORT_INT_ANONYMOUS=8480
export PORT_INT_VERT=80
export PORT_INT_VERTD=24153
export PORT_INT_COMPANION=8282
export PORT_INT_COBALT=80
export PORT_INT_COBALT_API=9000
export PORT_INT_SEARXNG=8080
export PORT_INT_IMMICH=2283

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
