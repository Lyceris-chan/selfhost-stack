#!/usr/bin/env bash
#
# Synchronization logic for external source repositories.

#######################################
# Clones or updates a git repository.
# Globals:
#   SUDO, FORCE_UPDATE
# Arguments:
#   repo_url: URL of the repository.
#   target_dir: Local directory to sync into.
#   version: Optional branch or tag (default: latest).
# Outputs:
#   Writes status messages to stdout.
# Returns:
#   0 on success, non-zero on failure.
#######################################
clone_repo() {
	local repo_url="$1"
	local target_dir="$2"
	local version="${3:-}"

	if [[ ! -d "${target_dir}/.git" ]]; then
		log_info "Cloning ${repo_url}..."
		"${SUDO}" mkdir -p "${target_dir}"
		"${SUDO}" chown "$(whoami)" "${target_dir}"
		local clone_opts="--depth 1"
		if [[ -n "${version}" ]] && [[ "${version}" != "latest" ]]; then
			clone_opts="--branch ${version} --depth 1"
		fi

		if git clone ${clone_opts} "${repo_url}" "${target_dir}"; then
			return 0
		fi

		if [[ -n "${version}" ]] && [[ "${version}" != "latest" ]]; then
			log_warn "Shallow clone failed for ${version}. Trying full clone..."
			if git clone "${repo_url}" "${target_dir}"; then
				if (cd "${target_dir}" && git fetch --all --tags && git checkout "${version}"); then
					return 0
				fi
			fi
		fi
	else
		if [[ "${FORCE_UPDATE:-false}" == "true" ]]; then
			log_info "Updating ${target_dir}..."
			if (cd "${target_dir}" && git fetch --all && git checkout -f "${version:-HEAD}" && git reset --hard "origin/${version:-$(git rev-parse --abbrev-ref HEAD)}" && git pull); then
				return 0
			fi
		else
			log_info "Repository exists at ${target_dir}. Ensuring correct version (${version})..."
			if [[ -n "${version}" ]] && [[ "${version}" != "latest" ]]; then
				(cd "${target_dir}" && git fetch --all --tags && git checkout -f "${version}") || true
			else
				(cd "${target_dir}" && git pull) || true
			fi
			return 0
		fi
	fi

	log_crit "Failed to sync repository ${repo_url}."
	return 1
}

#######################################
# Synchronizes all source repositories for the stack.
# Globals:
#   SRC_DIR, CONFIG_DIR, ENV_DIR, WG_PROFILES_DIR, SCRIPT_DIR, SUDO,
#   PATCHES_SCRIPT, SCRIBE_IMAGE_TAG, ODIDO_BOOSTER_IMAGE_TAG,
#   WIKILESS_IMAGE_TAG, COBALT_IMAGE_TAG
# Arguments:
#   None
# Outputs:
#   Writes progress and error messages to stdout/stderr.
# Returns:
#   0 on success, 1 on failure.
#######################################
sync_sources() {
	log_info "Synchronizing Source Repositories..."

	# Pre-sync connectivity check
	log_info "Verifying connectivity to source repositories..."
	local check_failed=false
	local repo_hosts=("https://github.com" "https://git.sr.ht" "https://codeberg.org")
	local repo_host
	for repo_host in "${repo_hosts[@]}"; do
		if ! curl -s --max-time 5 "${repo_host}" -o /dev/null >/dev/null 2>&1; then
			log_warn "Could not reach ${repo_host}. Sync may fail."
			check_failed=true
		fi
	done

	if [[ "${check_failed}" == "true" ]]; then
		if ! ask_confirm "One or more repository hosts are unreachable. Proceed anyway?"; then
			log_crit "Sync aborted by user due to connectivity issues."
			return 1
		fi
	fi

	# Clone repositories containing the Dockerfiles in parallel
	local pids=()

	(
		if clone_repo "https://git.sr.ht/~edwardloveall/scribe" "${SRC_DIR}/scribe" "${SCRIBE_IMAGE_TAG}"; then
			cat >"${SRC_DIR}/scribe/Dockerfile" <<'EOF'
# Multi-stage build for Scribe (Crystal + Lucky framework)
FROM node:16-alpine AS node_build
ARG PUID=1000
ARG PGID=1000
WORKDIR /tmp_build
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn prod

FROM 84codes/crystal:1.11.2-alpine AS lucky_build
ARG PUID=1000
ARG PGID=1000
RUN apk add --no-cache yaml-dev yaml-static zlib-dev zlib-static openssl-dev openssl-libs-static
WORKDIR /tmp_build
COPY shard.yml shard.lock ./
RUN shards install --production --skip-postinstall
COPY . .
COPY --from=node_build /tmp_build/public ./public
RUN crystal build --release --static src/start_server.cr -o start_server
RUN crystal build --release --static tasks.cr -o run_task

FROM alpine:latest
ARG PUID=1000
ARG PGID=1000
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=lucky_build /tmp_build/start_server /tmp_build/run_task ./
COPY --from=lucky_build /tmp_build/config ./config
COPY --from=node_build /tmp_build/public ./public
ENV LUCKY_ENV=production
EXPOSE 8080
CMD ["./start_server"]
EOF
		else
			exit 1
		fi
	) &
	pids+=($!)

	clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "${SRC_DIR}/odido-bundle-booster" "${ODIDO_BOOSTER_IMAGE_TAG}" &
	pids+=($!)
	clone_repo "https://github.com/Metastem/Wikiless" "${SRC_DIR}/wikiless" "${WIKILESS_IMAGE_TAG}" &
	pids+=($!)
	clone_repo "https://github.com/iv-org/invidious.git" "${SRC_DIR}/invidious" "latest" &
	pids+=($!)

	(
		if clone_repo "https://github.com/imputnet/cobalt.git" "${SRC_DIR}/cobalt" "${COBALT_IMAGE_TAG:-latest}"; then
			cat >"${SRC_DIR}/cobalt/web/Dockerfile" <<'EOF'
FROM node:24-alpine AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY . .
RUN pnpm install --frozen-lockfile
ARG WEB_DEFAULT_API
ENV WEB_DEFAULT_API=$WEB_DEFAULT_API
RUN pnpm --filter=@imput/cobalt-web build && \
    if [ -d "web/dist" ]; then mv web/dist web/build_output; else mv web/build web/build_output; fi

FROM nginx:alpine
COPY --from=build /app/web/build_output /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
		else
			exit 1
		fi
	) &
	pids+=($!)

	local success=true
	local pid
	for pid in "${pids[@]}"; do
		if ! wait "${pid}"; then
			success=false
		fi
	done

	if [[ "${success}" == "false" ]]; then
		log_crit "One or more source repositories failed to synchronize."
		return 1
	fi

	# Hub API (Local Service)
	if [[ -d "${SCRIPT_DIR}/lib/src/hub-api" ]]; then
		"${SUDO}" cp -r "${SCRIPT_DIR}/lib/src/hub-api" "${SRC_DIR}/hub-api"
	else
		log_crit "Hub API source not found at ${SCRIPT_DIR}/lib/src/hub-api"
		exit 1
	fi

	# Ensure patches.sh exists for volume mounting
	if [[ ! -f "${PATCHES_SCRIPT}" ]] || [[ ! -s "${PATCHES_SCRIPT}" ]]; then
		printf "#!/bin/sh\n" | "${SUDO}" tee "${PATCHES_SCRIPT}" >/dev/null
	fi
	"${SUDO}" chmod +x "${PATCHES_SCRIPT}"

	"${SUDO}" chmod -R 755 "${SRC_DIR}" "${CONFIG_DIR}"
	"${SUDO}" chmod -R 700 "${ENV_DIR}" "${WG_PROFILES_DIR}"
}
