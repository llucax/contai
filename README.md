# Contain AI! 📦🤖

`contai` is a very opinionated Docker-based sandbox for running AI CLI tools
for people paranoid enough to not wanting to give them access to their whole
system (i.e. normal people).

## Features

- **Sandboxed Environment**: Runs AI CLI tools in an isolated Docker container
  to protect your host system
- **Pre-installed AI CLI Tools**: Includes [OpenCode](https://opencode.ai/),
  [OpenAI Codex](https://developers.openai.com/codex/cli/),
  [GitHub Copilot](https://github.com/features/copilot/cli),
  [Google Gemini](https://github.com/google-gemini/gemini-cli),
  [Claude Code](https://www.claude.com/product/claude-code), and
  [RTK](https://github.com/rtk-ai/rtk) out of the box
- **Automatic RTK Setup**: Configures RTK at container startup for the shipped
  home-scoped tools, and when launching Copilot also installs its project-scoped
  `.github` integration in the current project
- **User Permission Mapping**: Maintains your host UID/GID for seamless file
  access and ownership
- **Persistent Home Directory**: Stores configuration and data in
  `~/.local/share/contai/home` across container sessions
- **Current Directory Mounting**: Automatically mounts and uses your current
  working directory
- **Development Tools Included**: Comes with ripgrep, bat, git, Python,
  Node.js, and other essential tools
- **On-demand Tool Installation**: Includes [pkgx](https://pkgx.dev/) for
  installing additional tools without root access
- **Symlink-friendly**: Can be symlinked as different tool names (e.g.,
  `opencode` symlink runs OpenCode directly)
- **Isolated GitHub MCP (optional)**: Optionally exposes the official GitHub MCP
  server to the AI tools from a separate, hardened sidecar, so your GitHub token
  never enters the tool's container (see the GitHub MCP Server section below)

## Build

To build the container image:

```sh
./build.sh
```

This will create a Docker image tagged as `contai:latest` with your host user's
UID/GID for proper file permissions.

To override the account created in the image, set `CONTAI_UID`, `CONTAI_USER`,
`CONTAI_GID`, and/or `CONTAI_GROUP` when building:

```sh
CONTAI_UID=1000 CONTAI_USER=developer CONTAI_GID=1000 CONTAI_GROUP=developers \
	./build.sh
```

## Installation

After building, you can install `contai` to your PATH:

```sh
# Create a bin directory in your home (if it doesn't exist)
mkdir -p ~/bin

# Copy the contai script (plus contai-mcp if you want the isolated GitHub MCP
# server described below; it must sit next to contai in your PATH)
cp contai contai-mcp ~/bin/

# Make sure ~/bin is in your PATH (add to ~/.bashrc or ~/.zshrc if needed)
export PATH="$HOME/bin:$PATH"
```

### Optional: Create Symlinks for Direct Tool Access

You can create symlinks to run specific AI tools directly:

```sh
cd ~/bin
ln -s contai opencode
ln -s contai copilot
ln -s contai codex
ln -s contai gemini
ln -s contai claude
ln -s contai rtk
```

Now you can run tools directly (e.g., `opencode` instead of `contai opencode`,
or `rtk` instead of `contai rtk`).

### Install AI Agent Instructions

To enable AI agents to work best inside the container (e.g., using `pkgx` for
missing tools instead of `apt-get`), install the provided `agent-instructions.md`
file to the appropriate location for your AI tool:

```sh
# Create the container's home config directories
home=~/.local/share/contai/home
mkdir -p "$home"
```

#### OpenCode

```sh
# OpenCode
mkdir -p "$home/.config/opencode"
cp agent-instructions.md "$home/.config/opencode/AGENTS.md"
```

#### Claude Code

```sh
mkdir -p "$home/.claude"
cp agent-instructions.md "$home/.claude/CLAUDE.md"
```

#### Google Gemini CLI

```sh
mkdir -p "$home/.gemini"
cp agent-instructions.md "$home/.gemini/GEMINI.md"
```

#### OpenAI Codex CLI

```sh
mkdir -p "$home/.codex"
cp agent-instructions.md "$home/.codex/AGENTS.md"
```

#### GitHub Copilot CLI

GitHub Copilot CLI only supports project-level instructions (not global), so
you would need to copy the file to each project's
`.github/copilot-instructions.md`.

## Usage

Run AI tools in the sandboxed environment:

```sh
# Run a specific tool
contai opencode

# Or use symlinks for direct access
opencode

# The container automatically mounts your current directory
cd /path/to/your/project
contai opencode
```

Your configuration and data will be persisted in `~/.local/share/contai/home`
across container sessions.

## RTK Setup

`contai` initializes RTK at container startup, not at image build time. This is
necessary because the generated RTK config lives in the mounted container home
directory (`~/.local/share/contai/home`) and, for Copilot, in the current
project.

On startup, `contai` automatically configures RTK for:

- Claude Code
- Google Gemini CLI
- OpenAI Codex CLI
- OpenCode

When you launch `copilot`, `contai` also installs RTK's project-scoped Copilot
integration in the current project root by creating:

- `.github/copilot-instructions.md`
- `.github/hooks/rtk-rewrite.json`

To check how many tokens RTK has saved across your sessions:

```sh
contai rtk gain
```

## Environment Variables

You can define environment variables in the container by writing to a
`~/.local/share/contai/env.list` file. The file is expected to have the
standard [docker `--env-file`
format](https://docs.docker.com/reference/cli/docker/container/run/#env).

## GitHub MCP Server (Isolated)

`contai` can give the AI tools access to GitHub through the official
[`github-mcp-server`](https://github.com/github/github-mcp-server) **without**
ever placing your GitHub token inside the AI tool's container. The token lives
only in a separate, hardened sidecar container (`contai-github-mcp`); the AI
container reaches it token-free over a private Docker network. A compromised MCP
server cannot read your host files, and the tool container never holds the token.

The sidecar is **enabled by the mere presence of a Personal Access Token (PAT)**
in your keyring — there is no separate on/off switch. On every launch, `contai`
starts the sidecar if (and only if) a PAT can be retrieved, then joins the
`contai-net` network so the endpoint `http://contai-github-mcp:8082/mcp` becomes
reachable. No PAT means no sidecar and unchanged behavior.

`contai` ships **no** opencode configuration: wiring opencode to the MCP (and any
write-gating policy) is your choice, as described below.

### 1. Store a GitHub PAT in your keyring

By default `contai` looks the token up with
`secret-tool lookup service github-mcp` (libsecret / Secret Service). Either:

- store it directly:

  ```sh
  secret-tool store --label='github-mcp PAT' service github-mcp
  ```

- or, with KeePassXC, add a custom attribute `service=github-mcp` to an entry and
  enable KeePassXC's Secret Service integration.

Use a least-privilege, fine-grained PAT (limit it to the repositories and
permissions you actually need) — the token's scope is the blast radius.

To stop using the MCP, remove the secret (or run `contai-mcp down`). To skip the
keyring lookup entirely, export `CONTAI_MCP_PAT_CMD=false`.

### 2. Wire opencode to the MCP

contai does not do this for you. Add the server to your opencode config —
globally at
`~/.local/share/contai/home/.config/opencode/opencode.json` (the contai home maps
to the container `$HOME`) or per project:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "github": {
      "type": "remote",
      "url": "http://contai-github-mcp:8082/mcp",
      "enabled": true,
      "oauth": false,
      "timeout": 15000
    }
  }
}
```

### 3. (Optional) Gate writes in opencode

With a read-write sidecar you can ask before write tools run. opencode MCP tools
are named `github_<tool>` and obey the normal permission rules (last match wins,
so the catch-all comes first):

```json
{
  "permission": {
    "github_*": "ask",
    "github_get_*": "allow",
    "github_list_*": "allow",
    "github_search_*": "allow",
    "github_*_read": "allow",
    "github_actions_get": "allow",
    "github_actions_list": "allow"
  }
}
```

This is a **model guardrail, not a containment boundary**: code the agent runs
via `bash` (e.g. `curl` to the unauthenticated endpoint) could still write within
the PAT's scope without a prompt. For a hard, non-bypassable guarantee, run the
sidecar read-only instead (`CONTAI_MCP_READONLY=1`, see below).

### Configuration knobs

| Variable / setting     | Default                                 | Effect                                                                                |
|------------------------|-----------------------------------------|---------------------------------------------------------------------------------------|
| `CONTAI_MCP_PAT_CMD`   | `secret-tool lookup service github-mcp` | PAT lookup command; also the de-facto enable switch (set to `false` to disable lookups) |
| `CONTAI_MCP_TOOLSETS`  | `all`                                   | GitHub toolsets to expose; trim for context/token budget                              |
| `CONTAI_MCP_READONLY`  | unset (read-write)                      | Set to any value for a hard, server-side read-only guarantee                          |
| `build_mcp` (build.sh) | `true`                                  | Set to `false` to skip building the sidecar image                                     |

### Security properties

- **Token isolation**: the PAT exists only in the sidecar's environment (fetched
  from the keyring at start, passed to Docker by name). It is absent from
  `env.list`, the AI container, process arguments, and disk.
- **No host filesystem**: the sidecar has zero bind mounts, so it cannot read
  host files; its only reach is the GitHub API (scoped by the PAT) and the AI
  container on `contai-net`. It publishes no ports to the host.
- **Hardening**: `--cap-drop=ALL`, `--security-opt=no-new-privileges`, read-only
  rootfs + tmpfs, non-root user, and pids/memory limits.
- For the strongest write protection, run the sidecar read-only with
  `CONTAI_MCP_READONLY=1` rather than relying on opencode's permission prompts.

## Known Issues

* Tested almost exclusively with OpenCode for now.

* When configuring MCP servers that need OAuth, for example using
  [`mcp-remote`](https://github.com/geelen/mcp-remote), for completing the
  OAuth flow, you need to open a browser on your host machine. For now, you need
  to run the OAuth flow outside the container, as the container does not
  have access to your host's browser, and then copy the credentials manually.

  For example:

  ```sh
  cp -r ~/.mcp-auth/* ~/.local/share/contai/home/.mcp-auth/
  ```

## Roadmap

- [ ] Add installer script and/or Debian package for easier installation
  (including symlinks to the shipped tools)
- [ ] Add pre-built images (needs some thought about how to deal with user IDs)
- [ ] Add auto-image build when invoking `contai` if image is not found
- [ ] Find a way to complete OAuth flows from within the container
- [ ] Integrate with `docker-compose` for easier multi-container setups, for
  cases where other services are needed, like MCP servers
- [ ] Support forwarding environment variables from the current environment.
- [ ] Add configuration file to be able to customize, for example:

  * Mapping of directories to mount into the container
  * Extra packages to install to the image
