FROM ubuntu:focal

# TASK [Upgrade the packages and restore the man command]

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get upgrade -y \
    && yes | unminimize 2>&1

ENV LANG='C.UTF-8'

# TASK [Enable the universe respository]

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -yq --no-install-recommends software-properties-common \
    && add-apt-repository universe \
    && apt-get update

# TASK [Ensure that build tools, utilities and tini are installed]
#
# Note: We do not install manpages-posix and manpages-posix-dev, which are
# non-free packages in Debian.

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -yq --no-install-recommends \
      apt-transport-https \
      apt-utils \
      gawk \
      bash-completion \
      build-essential \
      bzip2 \
      ca-certificates \
      clang \
      cmake \
      coreutils \
      cppcheck \
      curl \
      dialog \
      dirmngr \
      expect \
      gdb \
      git \
      gnupg2 \
      grep \
      htop \
      info \
      init-system-helpers \
      iproute2 \
      jq \
      less \
      libc6 \
      libgcc1 \
      libkrb5-3 \
      libgssapi-krb5-2 \
      libicu[0-9][0-9] \
      liblttng-ust[0-9] \
      libsecret-1-dev \
      libstdc++6 \
      lldb \
      llvm \
      locales \
      lsb-release \
      lsof \
      make \
      man-db \
      manpages \
      manpages-dev \
      nano \
      ncdu \
      net-tools \
      netcat \
      openssh-client \
      procps \
      psmisc \
      python-pip-whl \
      python3-dev \
      python3-pip \
      rsync \
      sed \
      snapd \
      strace \
      sudo \
      swig3.0 \
      tini \
      tree \
      unzip \
      vim \
      vim-doc \
      vim-tiny \
      valgrind \
      wget \
      xtail \
      xz-utils \
      zip \
      zlib1g \
    # Clean up
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# TASK [Ensure that at least the en_US.UTF-8 UTF-8 locale is available]

RUN if ! grep -o -E '^\s*en_US.UTF-8\s+UTF-8' /etc/locale.gen > /dev/null; then \
      echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; \
    fi

# TASK [Install ROS2 Desktop and its many dependencies]
#
# Note: We install this here rather than in the playbook to take advantage of
# dockerfile caching.

RUN export DEBIAN_FRONTEND=noninteractive \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -c -s) main" \
      | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update \
    && apt-get install -yq --no-install-recommends \
      python3-argcomplete \
      ros-dev-tools \
      ros-foxy-desktop

# TASK [Specify /home and /tmp as volumes]

VOLUME [ "/home", "/tmp" ]

# TASK [Create /entrypoint to hold entrypoint resources, and make /home writeable]

RUN mkdir --mode 777 '/entrypoint' && chmod 777 '/home'

# TASK [Initialize the user and group variables]

ARG USER_UID=1000
ARG USER_GID=1000
ARG DOCKER_GID=989
ARG USERNAME='devops'

# TASK [Create the default user]

RUN groupadd --system --gid "${DOCKER_GID}" docker \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --create-home --shell '/bin/bash' --uid "${USER_UID}" --gid "${USERNAME}" --groups 'sudo,docker' "${USERNAME}" \
    && echo -n "${USERNAME}:${USERNAME}" | chpasswd

COPY --chown="${USERNAME}:${USERNAME}" --chmod=644 [ "build/gitconfig", "/home/${USERNAME}/.gitconfig" ]

# TASK [Become the default user]

USER "${USERNAME}"

ENV USER="${USERNAME}" SHELL='/bin/bash' HOME="/home/${USERNAME}"

WORKDIR "/home/${USERNAME}"

# TASK [Initialize the repo clone variables]

ARG JUGGLEBOT_REPO_SSH_URL='git@github.com:joewalp/Jugglebot.git'
ARG REPO_CACHE_ID='0'

# TASK [Clone the Jugglebot git repo]

RUN --mount=type=ssh,mode=0666 mkdir --mode 700 "/home/${USERNAME}/.ssh" \
    && ssh-keyscan -t rsa github.com > /home/$USERNAME/.ssh/known_hosts \
    && git clone "${JUGGLEBOT_REPO_SSH_URL}" "/home/${USERNAME}/Jugglebot"

# TASK [Initialize the repo branch variable]

ARG JUGGLEBOT_REPO_BRANCH='main'

# TASK [Ensure that the specified branch is checked out]

WORKDIR "/home/${USERNAME}/Jugglebot"

RUN --mount=type=ssh,mode=0666 git checkout "${JUGGLEBOT_REPO_BRANCH}" \
    && git pull

WORKDIR "/home/${USERNAME}"

# TASK [Initialize the base setup and playbook variable]

ARG ENVIRONMENTS_DIR="/home/${USERNAME}/Jugglebot/environments"

# TASK [Run the ubuntu-common base setup and then the playbook]

RUN "${ENVIRONMENTS_DIR}/ubuntu_20.04-docker-native/base_setup_and_playbook.sh" \
      --environments-dir "${ENVIRONMENTS_DIR}" \
      --jugglebot-conda-env-filepath "${ENVIRONMENTS_DIR}/ubuntu-common/jugglebot_conda_env.yml" \
      --ansible-become-pass "${USERNAME}"

# TASK [Install entrypoint.sh]

COPY entrypoint.sh /entrypoint/

# TASK [Move the default user home directory into the /entrypoint directory]

RUN mv "/home/${USERNAME}" "/entrypoint/${USERNAME}"

# TASK [Specify additional environment variables for interactive sessions]

ENV SHELL='/usr/bin/zsh' GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# TASK [Use tini to corral processes, and run entrypoint.sh upon container start]
#
# Note: If "${HOME}" doesn't exist in the /home VOLUME, entrypoint.sh
# populates it from "/entrypoint/${USER}".

ENTRYPOINT [ "tini", "--", "/entrypoint/entrypoint.sh" ]

# TASK [Sleep to keep the container alive as a service]

CMD [ "sleep", "infinity" ]

# TASK [Retain a couple alternative CMDs for reference]
#
# The following tail CMD won't work because the container isn't producing system
# logs. (As I recall, the rsyslog package provisions the standard Ubuntu system
# logging.) We may end up using a tail command similar to this to expose a log
# of ROS2 application events.
#
# CMD [ "/usr/bin/tail", "-F", "/var/log/syslog" ]
#
# The following CMD can be helpful during debugging when paired with `docker
# run -it [...]` or `docker container start --attach [...]`.
#
# CMD [ "/usr/bin/zsh" ]
