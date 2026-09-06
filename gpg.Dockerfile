# GPG sidecar: a gpg-agent holding the secret keys, so that the AI container
# can sign commits without ever holding the key or its passphrase. It reaches
# the agent through the extra socket only, which gpg-agent serves in
# restricted mode: signing works there, exporting or re-protecting the key
# does not.
#
# Same Ubuntu as the main image, deliberately: the two halves of a gpg-agent
# connection are a client and an agent of the same GnuPG, and keeping them on
# one release keeps them on one version.
ARG UBUNTU_VERSION=25.10

FROM ubuntu:${UBUNTU_VERSION}

ARG UID
ARG USERNAME
ARG GID
ARG GROUPNAME

RUN userdel --force --remove ubuntu && \
	groupadd --gid ${GID} ${GROUPNAME} && \
	useradd --create-home --shell /bin/sh --gid ${GID} --uid ${UID} ${USERNAME}

RUN apt-get update && apt-get install -y --no-install-recommends \
	gnupg \
	&& rm -rf /var/lib/apt/lists/*

# No pinentry is installed, and that is the point: a passphrase this agent was
# not handed beforehand is one it cannot ask for, so an expired cache fails
# the signature instead of silently waiting on a prompt nobody will answer.

# Docker copies the ownership and the mode of this directory into the socket
# volume when it first mounts an empty one over it. Nothing here runs as root,
# so this is the only chance to get them right.
RUN mkdir -p /run/contai-gpg && \
	chown ${UID}:${GID} /run/contai-gpg && \
	chmod 700 /run/contai-gpg

COPY --chmod=755 contai-gpg-agent contai-gpg-preset /usr/local/bin/

# The key store, bind-mounted from the host. Both sockets of the agent land
# here too, as no /run/user/<uid> exists in this image for gpg to prefer, and
# the standard one staying in a directory the AI container cannot see is
# exactly where it belongs.
ENV GNUPGHOME=/gnupg

USER ${UID}:${GID}

ENTRYPOINT ["/usr/local/bin/contai-gpg-agent"]
