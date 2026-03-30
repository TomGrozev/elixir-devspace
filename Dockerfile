# Use the specified Red Hat Community of Practice DevSpaces base image
FROM registry.redhat.io/devspaces/udi-base-rhel9:3.26

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

USER 10001

WORKDIR /projects
