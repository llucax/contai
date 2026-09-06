#!/bin/sh
set -eu

# Optional sidecar images to build alongside the main one. Each name maps to
# "<name>.Dockerfile" and the tag "contai-<name>:latest", and is what
# contai-sidecar calls the service. Empty the list to build only contai
# itself.
sidecars='github-mcp gpg'

uid=${CONTAI_UID:-$(id -u)}
username=${CONTAI_USER:-$(id -un)}
gid=${CONTAI_GID:-$(id -g)}
groupname=${CONTAI_GROUP:-$(id -gn)}

docker build \
	-t contai:latest \
	--build-arg "UID=$uid" \
	--build-arg "USERNAME=$username" \
	--build-arg "GID=$gid" \
	--build-arg "GROUPNAME=$groupname" \
	--build-arg "HOME_DIR=${CONTAI_HOME:-$HOME}" \
	"$@" \
	-f Dockerfile \
	.

# The main build is done, so the positional parameters are free to collect the
# arguments of each sidecar build. Sidecar names hold no whitespace.
# shellcheck disable=SC2086
for sidecar in $sidecars
do
	set -- -t "contai-$sidecar:latest" -f "$sidecar.Dockerfile"

	# A sidecar that touches the host's files runs as the host user and
	# needs the same identity as the main image. The others declare no such
	# build args, and docker warns about arguments nothing consumes.
	case $sidecar in
	gpg)
		set -- "$@" \
			--build-arg "UID=$uid" \
			--build-arg "USERNAME=$username" \
			--build-arg "GID=$gid" \
			--build-arg "GROUPNAME=$groupname"
		;;
	esac

	docker build "$@" .
done
