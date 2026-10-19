FROM ubuntu:24.04

# install system dependencies
# (ldap-utils, libnss-ldapd, libpam-ldapd, nscd, nslcd are needed to resolve
#  training users against the environment's LDAP, as in the other apps)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        curl \
        git \
        dnsutils \
        gnupg \
        htop \
        locales \
        ldap-utils \
        libnss-ldapd \
        libpam-ldapd \
        less \
        nano \
        nscd \
        nslcd \
        openssh-client \
        python-is-python3 \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        rsync \
        time \
        unzip \
        vim \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_NZ -c -f UTF-8 -A /usr/share/locale/locale.alias en_NZ.UTF-8 \
    # 24.04 ships an "ubuntu" user at uid 1000; drop it so the uid can only
    # resolve to a training user through LDAP
    && userdel -r ubuntu

ENV LANG=en_NZ.utf8

# install kubectl, required for running on the k8s cluster
ARG KUBECTL_VERSION=v1.31.8
RUN curl -LO https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl \
    && mv kubectl /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# copy in ood k8s utils
ARG UTILS_HASH=6298fb01f7a7c66a8454e3f0fd74437a32491423
RUN git clone https://github.com/nesi/training-environment-k8s-utils.git /opt/ood-k8s-utils \
    && cd /opt/ood-k8s-utils \
    && git checkout $UTILS_HASH \
    && chmod +x /opt/ood-k8s-utils/files/* \
    && mv /opt/ood-k8s-utils/files/* /bin/ \
    && rm -rf /opt/ood-k8s-utils

# make a dummy module command to avoid warnings from ondemand job_script_content.sh
RUN echo "#!/bin/bash" > /bin/module \
    && chmod +x /bin/module

# ---------------------------------------------------------------------------
# VS Code (code-server) and the tools the Better Research Software lesson uses
# ---------------------------------------------------------------------------
ARG CODE_RELEASE=4.139.1
RUN mkdir -p /app/code-server \
    && curl -fsSL -o /tmp/code-server.tar.gz \
        "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-amd64.tar.gz" \
    && tar xf /tmp/code-server.tar.gz -C /app/code-server --strip-components=1 \
    && rm -f /tmp/code-server.tar.gz \
    && ln -s /app/code-server/bin/code-server /usr/local/bin/code-server \
    && code-server --version

# Extensions are installed once here and copied into each user's extensions
# directory on first start, so learners can still add their own. Pylance is
# Microsoft-only and not on Open VSX; basedpyright stands in as the language server.
RUN for ext in \
        ms-python.python@2026.4.0 \
        ms-python.debugpy@2026.6.0 \
        detachhead.basedpyright@1.40.1 \
        njpwerner.autodocstring@0.6.1 \
        mhutchie.git-graph@1.30.0 \
        ms-vscode.live-server@0.4.20 \
    ; do code-server --extensions-dir /opt/code-server/extensions --install-extension "$ext" || exit 1; done \
    && chmod -R a+rX /opt/code-server \
    && code-server --extensions-dir /opt/code-server/extensions --list-extensions --show-versions

# GitHub CLI, for learners whose network blocks GitHub SSH entirely
RUN curl -fsSL -o /usr/share/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/* \
    && gh --version

# Git defaults the lesson's setup check expects; learners still set their own
# user.name and user.email
RUN git config --system init.defaultBranch main \
    && git config --system core.editor "nano -w"

# GitHub SSH goes over port 443 (ssh.github.com), which works where outbound 22
# is blocked, and GitHub's published host keys are pinned so learners are not
# asked to trust an unverified fingerprint. The keys are committed rather than
# fetched from api.github.com at build time, which rate-limits CI runners (403);
# check them against https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
COPY ssh/github.conf /etc/ssh/ssh_config.d/github.conf
COPY ssh/known_hosts /etc/ssh/ssh_known_hosts
RUN chmod 0644 /etc/ssh/ssh_config.d/github.conf /etc/ssh/ssh_known_hosts \
    && ssh-keygen -lf /etc/ssh/ssh_known_hosts | grep -q "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

COPY code-server/settings.json /opt/code-server/settings.json


# `code` is what the lesson's setup check runs (`code --version`,
# `code --list-extensions`). code-server answers the same flags, and inside the
# integrated terminal it opens files in the running editor.
RUN printf '#!/bin/sh\nexec /usr/local/bin/code-server "$@"\n' > /usr/local/bin/code \
    && chmod 0755 /usr/local/bin/code

# ---------------------------------------------------------------------------
# Python packages the lesson installs
#
# Nothing is installed into the system Python. Episode 3 has learners create a
# venv and `pip install` into it, and the point lands only if the packages are
# missing until they do. Instead the wheels are downloaded into a local
# wheelhouse that pip consults alongside PyPI, so 30 learners installing at
# once still works if PyPI is slow or unreachable. Both the latest releases and
# the versions episode 7 pins are kept; numpy 2.0.0 has no wheels past
# Python 3.12, which is what Ubuntu 24.04 ships.
# ---------------------------------------------------------------------------
RUN python3 -m pip download --no-cache-dir --only-binary=:all: --dest /opt/wheelhouse \
        pandas matplotlib numpy pytest pytest-cov \
        mkdocs "mkdocstrings[python]" mkdocs-material \
    && python3 -m pip download --no-cache-dir --only-binary=:all: --dest /opt/wheelhouse \
        pandas==2.2.2 matplotlib==3.8.4 numpy==2.0.0 pytest==7.4.2 \
    && chmod -R a+rX /opt/wheelhouse \
    && printf '[global]\nfind-links = /opt/wheelhouse\n' > /etc/pip.conf \
    && python3 -m venv /tmp/check \
    && /tmp/check/bin/pip install --no-cache-dir --no-index pandas==2.2.2 matplotlib==3.8.4 numpy==2.0.0 pytest==7.4.2 \
    && /tmp/check/bin/python -c "import pandas, matplotlib, pytest; print('wheelhouse OK')" \
    && rm -rf /tmp/check

# ---------------------------------------------------------------------------
# Spacewalks, the lesson's example project
#
# Pinned to a commit of the lesson repo and checked by hash. It is shipped as
# plain files with no .git: learners run `git init` in it in episode 2. The
# .DS_Store, the space in "my code v2.py" and the hardcoded /home/sarah path
# are all deliberate teaching material - do not tidy them. script.sh.erb copies
# this to ~/spacewalks on first start; /opt/spacewalks stays as a clean copy.
# ---------------------------------------------------------------------------
ARG LESSON_HASH=cc78ee92c2cfef63a2cd3a242694f699a879d826
ARG SPACEWALKS_SHA256=6af7156e033bd1900659bf042e4b7efe45b35de9a8fb212d224640003ec58297
RUN curl -fsSL -o /tmp/spacewalks.zip \
        "https://raw.githubusercontent.com/carpentries-incubator/better-research-software/${LESSON_HASH}/learners/spacewalks.zip" \
    && echo "${SPACEWALKS_SHA256}  /tmp/spacewalks.zip" | sha256sum -c - \
    && unzip -q /tmp/spacewalks.zip -d /opt \
    && rm -rf /opt/__MACOSX /tmp/spacewalks.zip \
    && test -f "/opt/spacewalks/my code v2.py" \
    && test -f /opt/spacewalks/data.json \
    && test ! -e /opt/spacewalks/.git \
    && chmod -R a+rX /opt/spacewalks

EXPOSE 8443
