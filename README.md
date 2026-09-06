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
- **GPG Commit Signing (optional)**: Optionally signs commits through a
  `gpg-agent` running in its own sidecar, so the secret key and its passphrase
  stay outside the AI tool's container and all it can ask for is a signature
  (see the GPG Commit Signing section below)

## Requirements

On the host you need [Docker](https://docs.docker.com/engine/install/), usable
by your own user, and `bash` for the `contai` script itself. Any version of
bash will do, including the 3.2 that macOS still ships as `/bin/bash`. The
other scripts are POSIX `sh`. Everything else lives inside the container.

## Build

To build the container image:

```sh
./build.sh
```

This will create a Docker image tagged as `contai:latest` with your host user's
UID/GID for proper file permissions, plus one image per optional sidecar
(`contai-github-mcp:latest` and `contai-gpg:latest`). Trim the `sidecars` list
at the top of `build.sh` to build fewer of them; an image you never build is
simply a sidecar that never starts.

To override the account created in the image, set `CONTAI_UID`, `CONTAI_USER`,
`CONTAI_GID`, `CONTAI_GROUP`, and/or `CONTAI_HOME` when building:

```sh
CONTAI_UID=1000 CONTAI_USER=developer CONTAI_GID=1000 CONTAI_GROUP=developers \
	./build.sh
```

`CONTAI_HOME` is the home directory of that account, and defaults to your own
`$HOME`. `contai` mounts the persistent home at whatever `$HOME` is when it
runs, so overriding this at build time and not matching it at run time leaves
the container with a `$HOME` that nothing is mounted at, and anything written
there is lost when the container exits.

## Installation

After building, you can install `contai` to your PATH:

```sh
# Create a bin directory in your home (if it doesn't exist)
mkdir -p ~/bin

# Copy the contai script (plus contai-sidecar if you want the GitHub MCP
# server or the GPG signing agent described below; it must sit next to contai
# in your PATH)
cp contai contai-sidecar ~/bin/

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
across container sessions. The directory is mounted at your host home
directory's own path, so `$HOME` and everything below it is spelled the same
way inside and outside the container, and configuration that records absolute
paths stays valid. The contents are still the container's own: `~` inside the
container is the persistent directory above, not your host home directory.

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

Automatic RTK setup always disables telemetry during initialization so a
first-run consent prompt cannot block container startup. To enable telemetry,
configure RTK explicitly from the container:

```sh
contai rtk telemetry enable
```

This prompts for consent and stores the choice in the persistent container
home. The automatic startup initialization remains non-interactive.

## Environment Variables

You can define environment variables in the container by writing to a
`~/.local/share/contai/env.list` file. The file is expected to have the
standard [docker `--env-file`
format](https://docs.docker.com/reference/cli/docker/container/run/#env).

## Extra Docker Run Options

Arbitrary `docker run` options can be added in
`~/.local/share/contai/docker-run-opts.list`. Each line is **one argument**,
taken verbatim, so nothing needs quoting or escaping and paths may contain
spaces. Blank lines and lines starting with `#` are ignored.

Use the `--option=value` form so an option and its value fit on one line:

```
--volume=/data/models:/data/models:ro
--network=host
--gpus=all
```

An option that exists only in the two-word form takes two lines:

```
--add-host
myhost:10.0.0.1
```

These are passed after contai's own options, so they win where docker lets a
later option override an earlier one. That includes the options that make
this a sandbox at all: `--cap-drop=ALL`, `--security-opt=no-new-privileges`,
`--user`, and which directories are mounted. Putting `--privileged` or
`--user=root` in here gives away most of the point of contai, and so does
mounting this file, or any directory holding it, into the container: whatever
runs there could then choose the options of every later run.

Short of mounting it yourself, nothing running in the container can reach this
file, as only the current directory and the container home are mounted. The
remaining way to expose it is starting contai from a directory that contains
it, `~/.local` for instance, since the current directory is mounted writable:
whatever runs in the container could then pick the options of the next run,
and escape. contai refuses to start from such a directory rather than allowing
it.

That check exists to catch the easy mistake, not to be a boundary. It follows
symbolic links to find where the file really lives, but it cannot account for
every way of making it writable from the container, and does not try to.

### Mounting Directories

Two things are worth keeping in mind when adding `--volume`.

Create the host directory first. Docker creates a missing bind mount source
itself, but owned by `root`, which the container user then cannot write to.

Mounting a directory at the same path on both sides keeps absolute paths
recorded inside it valid on both sides. Python virtualenvs are a good
example: they name their interpreter by absolute path in `pyvenv.cfg` and
`bin/python`, so a virtualenv is only usable from both the host and the
container when its interpreter is reachable at a single path that exists in
both.

Prefer `:ro` for anything the host executes. A writable mount lets whatever
runs in the container replace a binary, a cached package or a sourced shell
snippet that the host later runs, which defeats the point of the sandbox.

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

To stop using the MCP, remove the secret (or run `contai-sidecar down
github-mcp`). To skip the keyring lookup entirely, export
`CONTAI_MCP_PAT_CMD=false`.

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
| `sidecars` (build.sh)  | `github-mcp gpg`                        | Drop `github-mcp` to skip building the sidecar image                                  |

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

## GPG Commit Signing

If your projects require signed commits, `contai` can sign them **without** the
secret key or its passphrase ever being inside the AI tool's container. The key
lives in a second sidecar (`contai-gpg`) running nothing but a `gpg-agent`, and
the tool container reaches that agent through a single socket shared in a Docker
volume.

That socket is `gpg-agent`'s *extra socket*, which the agent serves in
restricted mode. Restricted is not a contai policy but a `gpg-agent` one:
signing and decryption go through, while `EXPORT_KEY`, `IMPORT_KEY`,
`DELETE_KEY`, `PASSWD` and `PRESET_PASSPHRASE` are refused. In practice
`git commit -S` works inside the container and `gpg --export-secret-keys` there
answers `Forbidden`.

Like the MCP, the sidecar has **no on/off switch**: it starts when its key store
holds a secret key, and stays down otherwise.

### 1. Move the signing key into the sidecar's store

The store is `~/.local/share/contai/gpg`, and it is mounted into the gpg sidecar
and into nothing else. It needs the secret key and the public half of it, which
is what `gpg` reads in order to know which secret keys it has at all.

Coming from a key that already sits in the container home:

```sh
store=~/.local/share/contai/gpg
home=~/.local/share/contai/home

mkdir -p "$store/private-keys-v1.d"
chmod 700 "$store" "$store/private-keys-v1.d"

GNUPGHOME=$home/.gnupg gpg --export | GNUPGHOME=$store gpg --batch --import
mv "$home/.gnupg/private-keys-v1.d/"*.key "$store/private-keys-v1.d/"
```

Starting from a key on the host instead, export the signing subkey rather than
the whole key, so that the primary secret key stays where it is:

```sh
gpg --export YOUR_KEY_FINGERPRINT | GNUPGHOME=$store gpg --batch --import
gpg --export-secret-subkeys YOUR_KEY_FINGERPRINT |
	GNUPGHOME=$store gpg --batch --import
```

The AI container keeps the public half of the key in its own `~/.gnupg`, as
`git` and `gpg` there still have to find the key they are asking a signature
for. Only `private-keys-v1.d` moves.

### 2. Store the passphrase in your keyring

```sh
secret-tool store --label='contai GPG signing key' cli-id contai-gpg-secret
```

With KeePassXC, add a custom attribute `cli-id=contai-gpg-secret` to the entry
and enable KeePassXC's Secret Service integration.

`contai` presets that passphrase into the agent's restricted cache on every
launch, but only when the cache has run dry, so a keyring that asks before
handing a secret over asks once per cache lifetime rather than once per run.
The passphrase travels through a pipe into `docker exec` and nowhere else: not
through a file, an environment variable, or a command line, each of which every
other process of your user could read.

### 3. Point the container's git at the key

```sh
home=~/.local/share/contai/home
HOME=$home git config --global user.signingkey YOUR_KEY_FINGERPRINT
HOME=$home git config --global commit.gpgsign true
```

That is all. On the next `contai` run the sidecar comes up, `contai-bootstrap`
points the container's `gpg` at it, and signing works.

### Configuration knobs

| Variable / setting        | Default                                       | Effect                                                                |
|---------------------------|-----------------------------------------------|-----------------------------------------------------------------------|
| `CONTAI_GPG_SECRET_CMD`   | `secret-tool lookup cli-id contai-gpg-secret` | Passphrase lookup command (set to `false` to never look one up)       |
| `CONTAI_GPG_CACHE_TTL`    | `604800` (a week)                             | For how long the agent keeps the passphrase before it must be preset again |
| `sidecars` (build.sh)     | `github-mcp gpg`                              | Drop `gpg` to skip building the sidecar image                         |

### What this protects, and what it does not

- **The key does not leave the sidecar.** The store is bind-mounted into the
  gpg sidecar alone, and the restricted socket refuses every command that would
  hand a copy of the key out or change what protects it. Verify it yourself
  from inside the container: `gpg --export-secret-keys` fails with `Forbidden`.
- **The sidecar reaches nothing.** It runs with `--network none`,
  `--cap-drop=ALL`, `--security-opt=no-new-privileges`, and no bind mount other
  than the key store. There is no pinentry in the image either, so a passphrase
  it was not given beforehand is one it cannot be tricked into asking for.
- **It is not a boundary against the tool signing things.** For as long as the
  passphrase is cached, whatever runs in the container can have anything signed
  with that key, commits included. What it cannot do is take the key with it.
  Use a signing subkey you can revoke on its own, not one you would mind
  rotating, and shorten `CONTAI_GPG_CACHE_TTL` if a week of standing signing
  rights is more than you want to grant.
- **It is only as strong as your keyring.** If the Secret Service unlocks
  itself at login, as the GNOME Keyring `login` collection does by default, then
  anything running as you can read the passphrase and this buys little. It is
  worth the most with a backend that locks on its own, such as KeePassXC.
- **`gpg` in the container is noisier.** Listing keys prints
  `problem with fast path key listing: Forbidden - ignored`, because the bulk
  listing of keygrips is one of the commands the restricted socket refuses.
  Signing is unaffected.

To stop signing this way, run `contai-sidecar down gpg` and move
`private-keys-v1.d` back, or leave the store in place and remove the passphrase
from the keyring, which leaves the agent unable to unlock anything.

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
