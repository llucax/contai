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
├── gpg.Dockerfile         # GPG signing agent sidecar image definition
├── build.sh               # Build script (builds the main and sidecar images)
├── contai                 # Container runner script
├── contai-bootstrap       # Runtime container bootstrap for RTK and GPG setup
├── contai-sidecar         # Host script managing every sidecar
├── contai-gpg-agent       # Entry point of the GPG sidecar image
├── contai-gpg-preset      # Passphrase priming helper, GPG sidecar image only
└── agent-instructions.md  # Global agent instructions for end users
```

## Build Commands

| Command      | Description                                                              |
|--------------|--------------------------------------------------------------------------|
| `./build.sh` | Builds `contai:latest` plus one image per name in its `sidecars` list     |
| `./contai`   | Runs the container with current directory mounted                        |

### Building the Container

```sh
./build.sh
```

The build script passes host UID/GID to ensure proper file permissions inside the container.

It also builds one image per name in the `sidecars` list at the top of
`build.sh`: `<name>.Dockerfile` becomes `contai-<name>:latest`, which is what
`contai-sidecar` looks for. Trim the list to skip a sidecar. Only the sidecars
that touch host files get the UID/GID build args, since docker warns about
build args nothing consumes.

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
4. Verifying Claude Code is available to the mapped user: `./contai claude --version`
5. Verifying binary-installed tools work: `./contai rtk --version`
6. Verifying RTK bootstrap writes the expected runtime config for shipped tools
7. Verifying the GitHub MCP sidecar starts when a PAT is available
   (`contai-sidecar status github-mcp`) and that `./contai` joins the
   `contai-net` network
8. Verifying the GPG sidecar starts when its store holds a key
   (`contai-sidecar status gpg`), that the passphrase is cached
   (`docker exec contai-gpg contai-gpg-preset --check` succeeds), that
   `./contai git commit -S` produces a good signature, and that
   `./contai gpg --export-secret-keys` is refused with `Forbidden`

## Linting

No project-level linting is configured. However, the container includes these tools:
- Shell: `shellcheck`, `shfmt`
- Python: `ruff`, `flake8`, `pylint`, `mypy`, `black`, `isort`

To lint shell scripts locally (if shellcheck is installed):
```sh
shellcheck build.sh contai contai-bootstrap contai-sidecar \
	contai-gpg-agent contai-gpg-preset
shfmt -d build.sh contai contai-bootstrap contai-sidecar \
	contai-gpg-agent contai-gpg-preset
```

`shfmt` with default options wants `then` on the same line as `if`, which is
not the style used here, so it reports every script. Read its output for the
rest, not for that.

## Code Style Guidelines

### Shell Scripts

All shell scripts in this project follow these conventions:

#### Shebang and Error Handling
```sh
#!/bin/sh
set -eu
```
- Prefer `#!/bin/sh` (POSIX shell): these scripts run on the host, before
  the container exists, so the fewer things they need the better
- Use `#!/usr/bin/env bash` only when a script genuinely needs bash, and say
  why. `contai` does, for arrays: it builds lists of arguments of unknown
  length and has to keep every element quoted, which POSIX `sh` cannot express
  without either `eval` or juggling the positional parameters. Prefer `env`
  over `#!/bin/bash`, as bash is not at that path everywhere, and list the
  requirement in the README
- Always include `set -eu` immediately after the shebang
  - `-e`: Exit immediately on command failure
  - `-u`: Treat unset variables as errors
  - with bash, expand an array that may be empty as `"${a[@]+"${a[@]}"}"`.
    Plain `"${a[@]}"` is an unbound variable error under `-u` before bash
    4.4, and macOS still ships bash 3.2 as `/bin/bash`

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
container_home=$HOME

# Conditionals
if test -d "$home_dir"
then
	echo "Directory exists"
fi

# Multi-line commands
docker run \
	--rm \
	-it \
	-v "$home_dir:$container_home" \
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
ARG HOME_DIR
```
- Use ARG for build-time configuration
- Always support UID/GID mapping for host compatibility

The container home is the host's home directory, passed in as the `HOME_DIR`
build argument and defaulting to `$HOME` in `build.sh`. It has to be the same
path in three places, or state written below it is silently lost when the
container exits: the account's home in `useradd`, `ENV HOME`, and the volume
destination in `contai`. Derive it from `$HOME` in the runner rather than
repeating a literal, and keep `$HOME/.local/bin` on `PATH` for tools installed
there by `pkgx`.

Resist replacing it with a fixed path such as `/home/contai`. It looks tidier
and is one less build argument, but it makes an absolute path mean two
different things on the two sides of the mount, and it invalidates the
absolute paths that existing persistent homes already record: `nix` profile
symlinks, virtualenv interpreters, and the project lists that the AI tools
keep in their own configuration.

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

Claude Code should use the system-wide npm package in the image. The native
installer writes its launcher below `$HOME/.local/bin`, which is not a suitable
image-wide location when the image is built as `root`.

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
- `~/.local/share/contai/docker-run-opts.list`: Extra `docker run` options, one
  argument per line, appended after contai's own (see README.md)
- `~/.local/share/contai/gpg`: GnuPG home of the GPG sidecar, holding the secret
  keys. Mounted into that sidecar and never into the AI container

There is also one Docker volume, `contai-gpg-sock`, carrying the restricted
`gpg-agent` socket from the GPG sidecar to the AI container. It takes its
ownership from `/run/contai-gpg` in `gpg.Dockerfile` the first time it is
mounted, so a volume left over from an older image has to be removed rather
than reused.

## Sidecars

A sidecar is a separate container holding something the AI container must not
hold itself, and reachable from it through one narrow channel. `contai-sidecar`
manages all of them (`up`/`down`/`status`/`opts`), one service per block in the
script plus a name in its `services` list. Each block defines a container name,
a start hook that refuses when the service is not configured, a prime hook run
after every `up`, and an opts hook printing the `docker run` options the AI
container needs to reach it.

`contai` calls `contai-sidecar up` on every launch and then appends the output
of `contai-sidecar opts` to its own `docker run` options, so nothing about a
particular sidecar is hardcoded there. Their diagnostics are discarded, since
running without a sidecar is the normal case; run `contai-sidecar up` by hand to
see why one stayed down.

### github-mcp

`github-mcp.Dockerfile` builds `contai-github-mcp:latest`, a hardened sidecar
that bridges the official `github-mcp-server` (stdio) to an unauthenticated
Streamable HTTP endpoint via `supergateway`.

- It starts only when a PAT is retrievable (default:
  `secret-tool lookup service github-mcp`); no PAT means no sidecar and
  unchanged behavior.
- While it runs, `contai` attaches the AI container to the private `contai-net`
  network so it can reach `http://contai-github-mcp:8082/mcp`.
- The PAT lives only in the sidecar's environment (passed to Docker by name, not
  value). It never enters `env.list`, the AI container, argv, or disk.
- It runs with no host bind mounts, no published ports, `--cap-drop=ALL`,
  `--security-opt=no-new-privileges`, read-only rootfs, and pids/memory limits.
- contai ships no opencode configuration; wiring opencode to the MCP and any
  write-gating policy is the user's choice (see README.md).

Knobs: `CONTAI_MCP_PAT_CMD` (lookup command / enable), `CONTAI_MCP_TOOLSETS`
(default `all`), `CONTAI_MCP_READONLY` (set = read-only).

### gpg

`gpg.Dockerfile` builds `contai-gpg:latest`, a `gpg-agent` holding the secret
keys. Its two scripts, `contai-gpg-agent` and `contai-gpg-preset`, live in that
image only and are not installed on the host.

- It starts only when `~/.local/share/contai/gpg/private-keys-v1.d` holds a key.
- The AI container sees the agent through its *extra* socket, which `gpg-agent`
  serves in restricted mode: `PKSIGN` and `PKDECRYPT` work there, `EXPORT_KEY`,
  `IMPORT_KEY`, `DELETE_KEY`, `PASSWD` and `PRESET_PASSPHRASE` are refused. That
  restriction is `gpg-agent`'s own, not something contai enforces.
- `contai-bootstrap` writes a libassuan `%Assuan%` redirection file at
  `$(gpgconf --list-dirs socketdir)/S.gpg-agent` pointing at the mounted socket,
  and adds `no-autostart` to `~/.gnupg/gpg.conf` so a failure to reach the
  sidecar is loud instead of silently starting a keyless local agent.
- Priming happens on every `up`, including when the container was already
  running, so an expired cache is refilled. `contai-gpg-preset --check` decides
  whether a keyring lookup is needed at all.
- The passphrase must go into the agent's *restricted* cache
  (`gpg-preset-passphrase --restricted`): `gpg-agent` keys every cache entry by
  the restricted flag of the connection that made it, so an entry preset over
  the regular socket is invisible to a client signing over the extra one.
- Only `--max-cache-ttl` matters for preset entries; `--default-cache-ttl`
  governs passphrases typed into a pinentry, and the image ships none.

Knobs: `CONTAI_GPG_SECRET_CMD` (lookup command / enable),
`CONTAI_GPG_CACHE_TTL` (default a week).

## Adding New Features

When modifying this project:

1. **New shell scripts**: Follow the shell style guide above
2. **New Dockerfile layers**: Group related installations, maintain layer efficiency
3. **New AI tools**: Add to the appropriate Dockerfile install section
   (`npm install -g` for npm CLIs, release downloads for shipped binaries)
4. **New system tools**: Add to apt-get install section in Dockerfile
5. **Runtime tool initialization**: Keep startup logic in `contai-bootstrap`
   when it depends on the mounted container home or current project

Automatic RTK initialization always sets `RTK_TELEMETRY_DISABLED` to `1` so it
cannot block on a first-run consent prompt. Users can opt in separately with
`contai rtk telemetry enable` from an interactive container.

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
3. Recreate the sidecar: `contai-sidecar down github-mcp` (the next `./contai`
   recreates it)

### Adding a Sidecar
1. Write `<name>.Dockerfile` and add `<name>` to `sidecars` in `build.sh`
2. Add a block to `contai-sidecar` defining the container name and the start,
   prime and opts hooks, then add `<name>` to its `services` list
3. If the AI container needs anything at runtime to use it, put that in
   `contai-bootstrap`, keyed off whatever the opts hook mounts
4. Document it in README.md and in the Sidecars section above

### Debugging Container Issues
```sh
# Run container interactively
./contai bash

# Check installed tools
./contai which opencode
./contai node --version
```
