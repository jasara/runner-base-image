FROM composer:2.9.5 AS composer
FROM ubuntu:24.04

ARG KUBECTL_VERSION=1.32.2
ARG AWSCLI_VERSION=2.24.6
ARG GH_VERSION=2.87.0
ARG CLAUDE_VERSION=2.1.47
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y                              \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa        \
    && apt-get update -y                             \
    && apt-get install -y --no-install-recommends    \
    curl                                           \
    dbus                                           \
    kmod                                           \
    iproute2                                       \
    iputils-ping                                   \
    iptables-persistent                            \
    iptables                                       \
    cmake                                          \
    build-essential                                \
    pkg-config                                     \
    libssl-dev                                     \
    net-tools                                      \
    sudo                                           \
    systemd                                        \
    udev                                           \
    unzip                                          \
    ca-certificates                                \
    jq                                             \
    zip                                            \
    gnupg                                          \
    git-lfs                                        \
    git                                            \
    vim-tiny                                       \
    wget

RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

RUN install -m 0755 -d /etc/apt/keyrings                                                                            \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg      \
    && chmod a+r /etc/apt/keyrings/docker.gpg                                                                       \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg]                         \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable"         \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null                                                       \
    && apt-get update && apt-get install --no-install-recommends -y                                                 \
    docker-ce                                                                                                   \
    docker-ce-cli                                                                                               \
    containerd.io                                                                                               \
    docker-buildx-plugin                                                                                        \
    docker-compose-plugin                                                                                       \
    && apt-get clean && rm -rf /var/lib/apt/lists/*                                                                 \
    && systemctl enable docker.service

RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id

RUN adduser --disabled-password --gecos "" dev \
    && usermod -aG sudo,docker dev \
    && echo "%sudo ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    tmux \
    dbus-x11 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^session.*required.*pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/sshd

# Install PHP and dependencies (grpc built from source via PECL — see grpc/grpc#34278)
RUN apt-get update -y \
    && add-apt-repository ppa:ondrej/php \
    && apt-get update -y \
    && apt-get install -y php8.5-cli php8.5-dev php8.5-gd php8.5-opentelemetry php8.5-protobuf php8.5-pcov php8.5-simplexml php8.5-dom php8.5-curl php8.5-pgsql php8.5-zip php8.5-xml php8.5-redis php8.5-mbstring php8.5-gmp php8.5-sqlite3 php8.5-bcmath php8.5-intl zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Build grpc PHP extension from source (PPA package has PHP 8.5 symbol incompatibility)
# MAKEFLAGS parallelises the build; strip removes debug symbols (~50MB → ~5MB)
RUN pecl channel-update pecl.php.net \
    && MAKEFLAGS="-j$(nproc)" pecl install grpc \
    && strip --strip-debug "$(php -r 'echo ini_get("extension_dir");')/grpc.so" \
    && echo "extension=grpc.so" > /etc/php/8.5/mods-available/grpc.ini \
    && phpenmod grpc

COPY --from=composer /usr/bin/composer /usr/bin/composer

# Install Kubectl
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fLo /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Install AWS CLI
RUN case "$(dpkg --print-architecture)" in \
        amd64) AWS_ARCH="x86_64" ;; \
        arm64) AWS_ARCH="aarch64" ;; \
    esac \
    && mkdir /tmp/awscli_env/ \
    && cd /tmp/awscli_env/ \
    && wget "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" \
    && unzip "awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" \
    && ./aws/install \
    && rm -rf /tmp/awscli_env/

# Install PostgreSQL server and client
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-16 postgresql-client-16 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && systemctl enable postgresql

# Install Playwright system dependencies for Chromium
# These are the minimal deps needed - browser binaries are installed at runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libnss3 \
        libatk-bridge2.0-0 \
        libdrm2 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libgbm1 \
        libxkbcommon0 \
        libasound2t64 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
        -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${ARCH}"

# Install Infisical CLI
RUN curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash \
    && apt-get update \
    && apt-get install -y --no-install-recommends infisical \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Claude Code (move versioned binary system-wide so non-root users can execute it)
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
    && mv /root/.local/share/claude /usr/local/share/claude \
    && ln -sf /usr/local/share/claude/versions/${CLAUDE_VERSION} /usr/local/bin/claude \
    && rm -f /root/.local/bin/claude

COPY overlay/usr/local/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dev-setup

# Install jasara-cli (private repo — requires github_token build secret)
RUN --mount=type=secret,id=github_token \
    ARCH=$(dpkg --print-architecture) \
    && GH_TOKEN=$(cat /run/secrets/github_token) \
    gh release download \
        --repo jasara/jasara-cli \
        --pattern "*linux*${ARCH}*.tar.gz" \
        --dir /tmp/jasara \
    && tar -xzf /tmp/jasara/*.tar.gz -C /tmp/jasara \
    && find /tmp/jasara -maxdepth 1 -type f -perm /111 -exec install -m 0755 {} /usr/local/bin/jasara-cli \; \
    && rm -rf /tmp/jasara

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
