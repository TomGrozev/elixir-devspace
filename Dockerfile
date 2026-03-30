# Use the specified Red Hat Community of Practice DevSpaces base image
FROM quay.io/redhat-cop/devspaces-base:latest

# Set environment variables for Elixir installation
# Using OTP 26 and Elixir 1.15 as stable, well-supported versions. 
# You can adjust these versions if needed.
# renovate: depName=elixir-lang/elixir datasource=github-releases
ENV ELIXIR_VERSION=1.19.5 
# renovate: depName=erlang/otp datasource=github-releases
ENV OTP_VERSION=27.3.4.9
ENV REBAR3_VERSION=3.26.0
ENV LANG=C.UTF-8

# Install dependencies required to build Elixir/Erlang from source or install packages
# The base image likely has basic build tools, but we ensure key dependencies are present
USER root

# Update package lists and install build essentials, git, and other necessary tools
RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

RUN dnf update -y && \
  dnf install -y \
  # erlang \
  make \
  gcc \
  g++ \
  wget \
  tar \
  unzip \
  ncurses-devel \
  openssl-devel \
  inotify-tools \
  # --exclude=erlang-wx \
  && dnf clean all

# We'll install the build dependencies for erlang-odbc along with the erlang
# build process:
RUN set -xe \
  && OTP_DOWNLOAD_URL="https://github.com/erlang/otp/releases/download/OTP-${OTP_VERSION}/otp_src_${OTP_VERSION}.tar.gz" \
  && runtimeDeps='unixODBC \
  lksctp-tools ' \
  # wxGTK3 ' \
  && buildDeps='unixODBC-devel \
  perl \
  # SDL2 \
  lksctp-tools ' \
  # autoconf \
  # perl \
  # libtool \
  # flex \
  # bison \
  # m4 \
  # java-17-openjdk-devel ' \
  && dnf install -y $runtimeDeps $buildDeps \
  && curl -fSL -o otp-src.tar.gz "$OTP_DOWNLOAD_URL" \
  && export ERL_TOP="/usr/src/otp_src_${OTP_VERSION%%@*}" \
  && mkdir -vp $ERL_TOP \
  && tar -xzf otp-src.tar.gz -C $ERL_TOP --strip-components=1 \
  && rm otp-src.tar.gz \
  && ( cd $ERL_TOP \
  && ./otp_build autoconf \
  && ./configure --without-wx \
  && make -j$(nproc) \
  && make -j$(nproc) docs DOC_TARGETS=chunks \
  && make install install-docs DOC_TARGETS=chunks ) \
  && find /usr/local -name examples | xargs rm -rf \
  && dnf remove -y $buildDeps \
  && dnf clean all \
  && rm -rf $ERL_TOP

# Create a directory for downloading Elixir
WORKDIR /tmp/elixir-install

# Download and install Elixir using precompiled binaries
# Precompiled binaries are more reliable than building from source
RUN set -xe \
  && OTP_MAJOR="${OTP_VERSION%%.*}" \
  && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${OTP_MAJOR}.zip" \
  && curl -fSL -o elixir-precompiled.zip $ELIXIR_DOWNLOAD_URL \
  && mkdir -p /usr/local/lib/elixir \
  && unzip elixir-precompiled.zip -d /usr/local/lib/elixir \
  && rm elixir-precompiled.zip \
  && ln -s /usr/local/lib/elixir/bin/elixir /usr/local/bin/elixir \
  && ln -s /usr/local/lib/elixir/bin/elixirc /usr/local/bin/elixirc \
  && ln -s /usr/local/lib/elixir/bin/iex /usr/local/bin/iex \
  && ln -s /usr/local/lib/elixir/bin/mix /usr/local/bin/mix

# Verify installation
RUN elixir --version

ENV PROFILE_EXT=/etc/profile.d/udi_environment.sh 

RUN dnf -y -q install --setopt=tsflags=nodocs \
  git ca-certificates jq \
  fuse-overlayfs container-tools \
  bash bash-completion tar gzip unzip bzip2 which shadow-utils findutils wget sudo git-lfs procps-ng vim neovim && \
  dnf -y -q reinstall shadow-utils ca-certificates && \
  dnf -y -q update && \
  dnf -y -q clean all --enablerepo='*' && \
  dnf -y -q clean all && rm -rf /var/cache/yum && \
  mkdir -p /opt && \
  # add user and configure it
  useradd -u 1000 -G wheel,root -d /home/user --shell /bin/bash -m user && \
  # $PROFILE_EXT contains all additions made to the bash environment
  touch ${PROFILE_EXT} && \
  # Setup $PS1 for a consistent and reasonable prompt
  touch /etc/profile.d/udi_prompt.sh && \
  echo "export PS1='\W \`git branch --show-current 2>/dev/null | sed -r -e \"s@^(.+)@\(\1\) @\"\`$ '" >> /etc/profile.d/udi_prompt.sh && \
  # Change permissions to let any arbitrary user
  mkdir -p /projects && \
  for f in "${HOME}" "/etc/passwd" "/etc/group" "/projects"; do \
  echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
  chmod -R g+rwX ${f}; \
  done && \
  # Generate passwd.template
  cat /etc/passwd | \
  sed s#user:x.*#user:x:\${USER_ID}:\${GROUP_ID}::\${HOME}:/bin/bash#g \
  > ${HOME}/passwd.template && \
  cat /etc/group | \
  sed s#root:x:0:#root:x:0:0,\${USER_ID}:#g \
  > ${HOME}/group.template && \
  # Define user directory for binaries
  mkdir -p /home/user/.local/bin

RUN \
  ## Rootless podman install #2: install podman buildah skopeo e2fsprogs (above)
  ## Rootless podman install #3: tweaks to make rootless buildah work
  touch /etc/subgid /etc/subuid  && \
  chmod g=u /etc/subgid /etc/subuid /etc/passwd  && \
  echo user:10000:65536 > /etc/subuid  && \
  echo user:10000:65536 > /etc/subgid && \
  ## Rootless podman install #4: adjust storage.conf to enable Fuse storage.
  sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf && \
  mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers; \
  touch /var/lib/shared/overlay-images/images.lock; \
  touch /var/lib/shared/overlay-layers/layers.lock && \
  ## Rootless podman install #5: rename podman to allow the execution of 'podman run' using
  ##                             kubedock but 'podman build' using podman.orig
  mv /usr/bin/podman /usr/bin/podman.orig && \
  # Docker alias
  echo 'alias docker=podman' >> ${PROFILE_EXT}

# A last pass to make sure that an arbitrary user can write in $HOME
RUN chgrp -R 0 /home && chmod -R g=u /home

USER 10001
ENV HOME=/home/user
# /usr/libexec/podman/catatonit is used to reap zombie processes
ENTRYPOINT ["/usr/libexec/podman/catatonit","--","/entrypoint.sh"]
WORKDIR /projects
CMD tail -f /dev/null
