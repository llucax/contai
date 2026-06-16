# GitHub MCP sidecar: bridges the official github-mcp-server (stdio) to an
# unauthenticated Streamable HTTP endpoint so the opencode container can reach
# it over a private Docker network without ever holding the PAT.
#
# Pin the upstream server image for reproducibility; bump deliberately.
FROM ghcr.io/github/github-mcp-server:v1.3.0 AS ghmcp

FROM node:24-alpine

RUN npm install -g supergateway@latest

COPY --from=ghmcp /server/github-mcp-server /usr/local/bin/github-mcp-server

USER node
EXPOSE 8082

# supergateway spawns the child with the inherited environment, so the
# GITHUB_PERSONAL_ACCESS_TOKEN supplied at runtime reaches github-mcp-server.
# Token and toolsets are NOT baked into the image; they are passed at `docker
# run` time. Resulting endpoint: http://contai-github-mcp:8082/mcp
ENTRYPOINT ["supergateway", \
	"--stdio", "github-mcp-server stdio", \
	"--outputTransport", "streamableHttp", \
	"--port", "8082"]
