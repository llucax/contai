# AGENTS.md

This file provides guidance for AI coding agents working in the contai repository.

## Project Overview

contai is a Docker-based sandbox for running AI CLI tools (OpenCode, GitHub Copilot,
OpenAI Codex, Google Gemini, Claude Code, RTK) in isolation. It's a minimal project
with shell scripts and a Dockerfile - no package.json, no TypeScript, no complex build
system.

Read README.md for complete project documentation including features and usage.

## Project Structure

```
contai/
├── AGENTS.md              # This file - AI agent instructions
├── README.md              # Project documentation
├── Dockerfile             # Container definition with dev tools
├── github-mcp.Dockerfile  # Isolated GitHub MCP sidecar image definition
├── build.sh               # Build script (builds both images)
├── contai                 # Container runner script
├── contai-bootstrap       # Runtime container bootstrap for RTK setup
├── contai-mcp             # Host script managing the GitHub MCP sidecar
└── agent-instructions.md  # Global agent instructions for end users
```

## Build Commands

| Command      | Description                                              |
|--------------|----------------------------------------------------------|
| `./build.sh` | Builds `contai:latest` and `contai-github-mcp:latest`    |
| `./contai`   | Runs the container with current directory mounted        |

### Building the Container

```sh
./build.sh
```

The build script passes host UID/GID to ensure proper file permissions inside the container.

It also builds the optional `contai-github-mcp:latest` sidecar image (the
isolated GitHub MCP server). Set `build_mcp=false` in `build.sh` to skip it.

### Running the Container

```sh
./contai opencode    # Run a specific AI tool
./contai             # Start container shell
```

## Testing

This project has no test suite. Changes should be verified by:
1. Building the container: `./build.sh`
2. Running the container and testing functionality: `./contai`
3. Verifying the AI tools work: `./contai opencode --version`
4. Verifying binary-installed tools work: `./contai rtk --version`
5. Verifying RTK bootstrap writes the expected runtime config for shipped tools
6. Verifying the GitHub MCP sidecar starts when a PAT is available
   (`contai-mcp status`) and that `./contai` joins the `contai-net` network

## Linting

No project-level linting is configured. However, the container includes these tools:
- Shell: `shellcheck`, `shfmt`
- Python: `ruff`, `flake8`, `pylint`, `mypy`, `black`, `isort`

To lint shell scripts locally (if shellcheck is installed):
```sh
shellcheck build.sh contai contai-bootstrap contai-mcp
shfmt -d build.sh contai contai-bootstrap contai-mcp
```

## Code Style Guidelines

### Shell Scripts

All shell scripts in this project follow these conventions:

#### Shebang and Error Handling
```sh
#!/bin/sh
set -eu
```
- Always use `#!/bin/sh` (POSIX shell), not `#!/bin/bash`
- Always include `set -eu` immediately after the shebang
  - `-e`: Exit immediately on command failure
  - `-u`: Treat unset variables as errors

#### Variable Naming
- Use lowercase with underscores: `data_dir`, `home_dir`, `env_file`
- Never use camelCase or UPPER_CASE for local variables

#### Quoting
- Always quote variables in strings: `"$home_dir"`
- Use double quotes for strings containing variables
- Single quotes for literal strings without variables

#### Command Substitution
- Use `$(command)` syntax, not backticks
- Example: `$(id -u)`, `$(basename "$0")`

#### Conditionals
- Use `test` command or `[` for conditions: `if test "$tool" = "contai"`
- Use `=` for string comparison, not `==`

#### Indentation
- Use tabs for indentation, not spaces
- Indent continuation lines in multi-line commands

#### Line Continuation
- Use backslash `\` for multi-line commands
- Place backslash at end of line with no trailing whitespace

#### Example Shell Script Pattern
```sh
#!/bin/sh
set -eu

# Variables
data_dir=~/.local/share/contai
home_dir=$data_dir/home

# Conditionals
if test -d "$home_dir"
then
	echo "Directory exists"
fi

# Multi-line commands
docker run \
	--rm \
	-it \
	-v "$home_dir:$HOME" \
	contai:latest
```

### Dockerfile

#### Base Image
- Use explicit Ubuntu version: `ubuntu:25.10`
- Never use `ubuntu:latest` - specify version number
- Update version when new Ubuntu releases are available

#### Build Arguments
```dockerfile
ARG UBUNTU_VERSION=25.10
ARG UID
ARG USERNAME
ARG GID
ARG GROUPNAME
```
- Use ARG for build-time configuration
- Always support UID/GID mapping for host compatibility

#### RUN Commands
- Chain related commands with `&&` in single RUN layers
- Use backslash `\` for line continuation
- Indent continuation lines with tabs
- Group package installations logically

#### Package Installation Order
1. System packages via `apt-get`
2. Python packages via `pip` (with `--break-system-packages`)
3. Node.js setup and npm packages
4. Binary downloads and installations

#### Example Dockerfile Pattern
```dockerfile
ARG UBUNTU_VERSION=25.10

FROM ubuntu:${UBUNTU_VERSION}

ARG UID
ARG GID

RUN apt-get update && apt-get install -y \
	package1 \
	package2 \
	package3

RUN pip install --break-system-packages \
	python-package1 \
	python-package2
```

## Data Directories

The container uses these host directories:
- `~/.local/share/contai/home`: Persistent home directory
- `~/.local/share/contai/env.list`: Environment variables for container

## GitHub MCP Sidecar

`github-mcp.Dockerfile` builds `contai-github-mcp:latest`, a hardened sidecar
that bridges the official `github-mcp-server` (stdio) to an unauthenticated
Streamable HTTP endpoint via `supergateway`. The host script `contai-mcp`
manages its lifecycle (`up`/`down`/`status`).

Runtime behavior, wired from `contai`:
- `contai` calls `contai-mcp up` on every launch. The sidecar starts only when a
  PAT is retrievable (default: `secret-tool lookup service github-mcp`); no PAT
  means no sidecar and unchanged behavior.
- When the sidecar is running, `contai` attaches the opencode container to the
  private `contai-net` network so it can reach
  `http://contai-github-mcp:8082/mcp`.
- The PAT lives only in the sidecar's environment (passed to Docker by name, not
  value). It never enters `env.list`, the opencode container, argv, or disk.
- The sidecar runs with no host bind mounts, no published ports, `--cap-drop=ALL`,
  `--security-opt=no-new-privileges`, read-only rootfs, and pids/memory limits.
- contai ships no opencode configuration; wiring opencode to the MCP and any
  write-gating policy is the user's choice (see README.md).

Knobs: `CONTAI_MCP_PAT_CMD` (lookup command / enable), `CONTAI_MCP_TOOLSETS`
(default `all`), `CONTAI_MCP_READONLY` (set = read-only), and `build_mcp` in
`build.sh`.

## Adding New Features

When modifying this project:

1. **New shell scripts**: Follow the shell style guide above
2. **New Dockerfile layers**: Group related installations, maintain layer efficiency
3. **New AI tools**: Add to the appropriate Dockerfile install section
   (`npm install -g` for npm CLIs, release downloads for shipped binaries)
4. **New system tools**: Add to apt-get install section in Dockerfile
5. **Runtime tool initialization**: Keep startup logic in `contai-bootstrap`
   when it depends on the mounted container home or current project

**Important**: When making any changes to the project, especially structural changes
(adding/removing files, changing build process, modifying project conventions), update
this AGENTS.md file to reflect those changes.

## Common Tasks

### Adding a New AI Tool
1. Determine whether the tool should be installed from npm or release binaries
2. Add it to the matching install section in Dockerfile
3. Rebuild: `./build.sh`
4. Test: `./contai <tool-name>`

### Adding System Packages
1. Add package to `apt-get install -y` section
2. Rebuild and test

### Updating the GitHub MCP Server Version
1. Bump the pinned `ghcr.io/github/github-mcp-server:<tag>` in `github-mcp.Dockerfile`
2. Rebuild: `./build.sh`
3. Recreate the sidecar: `contai-mcp down` (the next `./contai` recreates it)

### Debugging Container Issues
```sh
# Run container interactively
./contai bash

# Check installed tools
./contai which opencode
./contai node --version
```
