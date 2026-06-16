#!/bin/sh
set -eu

# Build the optional github-mcp sidecar image. Set to false to skip.
build_mcp=true

docker build \
	-t contai:latest \
	--build-arg "UID=${CONTAI_UID:-$(id -u)}" \
	--build-arg "USERNAME=${CONTAI_USER:-$(id -un)}" \
	--build-arg "GID=${CONTAI_GID:-$(id -g)}" \
	--build-arg "GROUPNAME=${CONTAI_GROUP:-$(id -gn)}" \
	"$@" \
	-f Dockerfile \
	.

if test "$build_mcp" = "true"
then
	docker build \
		-t contai-github-mcp:latest \
		-f github-mcp.Dockerfile \
		.
fi
