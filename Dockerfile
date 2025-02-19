FROM ghcr.io/hostinger/fireactions:0.3.0 AS fireactions
FROM composer:2.8.5 AS composer
FROM ubuntu:24.04

ARG RUNNER_VERSION=2.322.0
ARG KUBECTL_VERSION=1.32.2
ARG AWSCLI_VERSION=2.24.6
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
    openssh-server                                 \
    haveged                                        \
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

RUN systemctl enable haveged.service

RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

RUN adduser --disabled-password --gecos "" --uid 1001 runner  \
    && groupadd docker --gid 121                              \
    && usermod -aG docker runner                              \
    && usermod -aG sudo runner                                \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers

RUN case "$TARGETARCH" in amd64|x86_64|i386) export RUNNER_ARCH="x64";; arm64) export RUNNER_ARCH="arm64";; esac                                                         \
    && mkdir -p /opt/runner /opt/hostedtoolcache && cd /opt/runner                                                                                                 \
    && curl -fLo runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz && rm -rf runner.tar.gz                                                                                                             \
    && ./bin/installdependencies.sh                                                                                                                                \
    && chown -R runner:docker /opt/runner /opt/hostedtoolcache                                                                                                     \
    && chmod -R 777 /opt/hostedtoolcache

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

RUN echo 'root:fireactions' | chpasswd                                                                   \
    && sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/'            /etc/ssh/sshd_config

RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id

COPY overlay/etc /etc
COPY --from=fireactions /usr/bin/fireactions /usr/bin/fireactions

RUN systemctl enable fireactions.service

# Install PHP and dependencies
RUN apt-get update -y \
    && add-apt-repository ppa:ondrej/php \
    && apt-get update -y \
    && apt-get install php8.4-cli php8.4-gd php8.4-opentelemetry php8.4-grpc php8.4-protobuf php8.4-pcov php8.4-simplexml php8.4-dom php8.4-curl php8.4-pgsql php8.4-zip php8.4-xml php8.4-redis php8.4-mbstring php8.4-gmp php8.4-sqlite3 php8.4-bcmath php8.4-intl -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/bin/composer

# Install Kubectl
RUN mkdir /tmp/kubectl_env/ && \
    cd /tmp/kubectl_env/ && \
    curl -LO "https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    rm -rf /tmp/kubectl_env/

# Install AWS cli
RUN mkdir /tmp/awscli_env/ && \
    cd /tmp/awscli_env/ && \
    wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" && \
    unzip awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip && \
    ./aws/install && \
    rm -rf /tmp/awscli_env/
