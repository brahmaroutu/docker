#
# DO NOT EDIT - GENERATED BY project/generate-dockerfile.sh
#
# This file describes the standard way to build Docker, using docker
#
# Usage:
#
# # Assemble the full dev environment. This is slow the first time.
# docker build -t docker .
#
# # Mount your source in an interactive container for quick testing:
# docker run -v `pwd`:/go/src/github.com/docker/docker --privileged -i -t docker bash
#
# # Run the test suite:
# docker run --privileged docker hack/make.sh test
#
# # Publish a release:
# docker run --privileged \
#  -e AWS_S3_BUCKET=baz \
#  -e AWS_ACCESS_KEY=foo \
#  -e AWS_SECRET_KEY=bar \
#  -e GPG_PASSPHRASE=gloubiboulga \
#  docker hack/release.sh
#
# Note: Apparmor used to mess with privileged mode, but this is no longer
# the case. Therefore, you don't have to disable it anymore.
#

FROM ibmcom/gccgo_p:latest
ENV CGO_ENABLED 1
ENV USE_GCCGO  1
MAINTAINER Tianon Gravi <admwiggin@gmail.com> (@tianon)
# Packaged dependencies
RUN apt-get update && apt-get install -y \
       apparmor \
       aufs-tools \
       automake \
       bash-completion \
       btrfs-tools \
       build-essential \
       curl \
       dpkg-sig \
       git \
       iptables \
       libapparmor-dev \
       libcap-dev \
       libsqlite3-dev \
       mercurial \
       parallel \
       python-mock \
       python-pip \
       python-websocket \
       reprepro \
       ruby \
       ruby-dev \
       s3cmd \
       --no-install-recommends

# Get lvm2 source for compiling statically
RUN git clone -b v2_02_103 https://git.fedorahosted.org/git/lvm2.git /usr/local/lvm2
# see https://git.fedorahosted.org/cgit/lvm2.git/refs/tags for release tags

RUN rm -rf /usr/local/lvm2
RUN git clone --no-checkout git://git.fedorahosted.org/git/lvm2.git /usr/local/lvm2 && cd /usr/local/lvm2 && git checkout -q v2_02_103
RUN curl -o /usr/local/lvm2/autoconf/config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
RUN curl -o /usr/local/lvm2/autoconf/config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'
# Compile and install lvm2
RUN cd /usr/local/lvm2 \
       && ./configure --enable-static_link \
       && make device-mapper \
       && make install_device-mapper
# see https://git.fedorahosted.org/cgit/lvm2.git/tree/INSTALL

# Install lxc
ENV LXC_VERSION 1.1.2
RUN mkdir -p /usr/src/lxc \
       && curl -sSL https://linuxcontainers.org/downloads/lxc/lxc-${LXC_VERSION}.tar.gz | tar -v -C /usr/src/lxc/ -xz --strip-components=1
RUN cd /usr/src/lxc \
       && ./configure \
       && make \
       && make install \
       && ldconfig

ENV GOPATH /go:/go/src/github.com/docker/docker/vendor


# Update this sha when we upgrade to go 1.5.0
ENV GO_TOOLS_COMMIT 069d2f3bcb68257b627205f0486d6cc69a231ff9
# Grab Go's cover tool for dead-simple code coverage testing
# Grab Go's vet tool for examining go code to find suspicious constructs
# and help prevent errors that the compiler might not catch
RUN git clone https://github.com/golang/tools.git /go/src/golang.org/x/tools \
       && (cd /go/src/golang.org/x/tools && git checkout -q $GO_TOOLS_COMMIT) \
       && go install -v golang.org/x/tools/cmd/cover \
       && go install -v golang.org/x/tools/cmd/vet

# TODO replace FPM with some very minimal debhelper stuff
RUN apt-get install -y libffi-dev
RUN gem install --no-rdoc --no-ri fpm --version 1.3.2

# Install registry
ENV REGISTRY_COMMIT 2317f721a3d8428215a2b65da4ae85212ed473b4
RUN set -x \
       && export GOPATH="$(mktemp -d)" \
       && git clone https://github.com/docker/distribution.git "$GOPATH/src/github.com/docker/distribution" \
       && (cd "$GOPATH/src/github.com/docker/distribution" && git checkout -q "$REGISTRY_COMMIT") \
       && GOPATH="$GOPATH/src/github.com/docker/distribution/Godeps/_workspace:$GOPATH" \
               go build -o /usr/local/bin/registry-v2 github.com/docker/distribution/cmd/registry \
       && rm -rf "$GOPATH"

# Install notary server
ENV NOTARY_COMMIT 77bced079e83d80f40c1f0a544b1a8a3b97fb052
RUN set -x \
       && export GOPATH="$(mktemp -d)" \
       && git clone https://github.com/docker/notary.git "$GOPATH/src/github.com/docker/notary" \
       && (cd "$GOPATH/src/github.com/docker/notary" && git checkout -q "$NOTARY_COMMIT") \
       && GOPATH="$GOPATH/src/github.com/docker/notary/Godeps/_workspace:$GOPATH" \
               go build -o /usr/local/bin/notary-server github.com/docker/notary/cmd/notary-server \
       && rm -rf "$GOPATH"

# Get the "docker-py" source so we can run their integration tests
ENV DOCKER_PY_COMMIT 91985b239764fe54714fa0a93d52aa362357d251
RUN git clone https://github.com/docker/docker-py.git /docker-py \
       && cd /docker-py \
       && git checkout -q $DOCKER_PY_COMMIT

# Setup s3cmd config
RUN { \
               echo '[default]'; \
               echo 'access_key=$AWS_ACCESS_KEY'; \
               echo 'secret_key=$AWS_SECRET_KEY'; \
       } > ~/.s3cfg

# Set user.email so crosbymichael's in-container merge commits go smoothly
RUN git config --global user.email 'docker-dummy@example.com'

# Add an unprivileged user to be used for tests which need it
RUN groupadd -r docker
RUN useradd --create-home --gid docker unprivilegeduser

VOLUME /var/lib/docker
WORKDIR /go/src/github.com/docker/docker
ENV DOCKER_BUILDTAGS apparmor selinux 

# Let us use a .bashrc file
RUN ln -sfv $PWD/.bashrc ~/.bashrc

# Register Docker's bash completion.
RUN ln -sv $PWD/contrib/completion/bash/docker /etc/bash_completion.d/docker
# Get useful and necessary Hub images so we can "docker load" locally instead of pulling
COPY contrib/download-frozen-image.sh /go/src/github.com/docker/docker/contrib/
RUN ./contrib/download-frozen-image.sh /docker-frozen-images \
         ibmcom/busybox_p:latest \
         ibmcom/hello-world_p:frozen \
         ibmcom/unshare_p:latest
# see also "hack/make/.ensure-frozen-images" (which needs to be updated any time this list is)

# Download man page generator
RUN set -x \
       && export GOPATH="$(mktemp -d)" \
       && git clone -b v1.0.1 https://github.com/cpuguy83/go-md2man.git "$GOPATH/src/github.com/cpuguy83/go-md2man" \
       && git clone -b v1.2 https://github.com/russross/blackfriday.git "$GOPATH/src/github.com/russross/blackfriday" \
       && go get -v -d github.com/cpuguy83/go-md2man \
       && go build -v -o /usr/local/bin/go-md2man github.com/cpuguy83/go-md2man \
       && rm -rf "$GOPATH"

# Download toml validator
ENV TOMLV_COMMIT 9baf8a8a9f2ed20a8e54160840c492f937eeaf9a
RUN set -x \
       && export GOPATH="$(mktemp -d)" \
       && git clone https://github.com/BurntSushi/toml.git "$GOPATH/src/github.com/BurntSushi/toml" \
       && (cd "$GOPATH/src/github.com/BurntSushi/toml" && git checkout -q "$TOMLV_COMMIT") \
       && go build -v -o /usr/local/bin/tomlv github.com/BurntSushi/toml/cmd/tomlv \
       && rm -rf "$GOPATH"

# Build/install the tool for embedding resources in Windows binaries
ENV RSRC_COMMIT e48dbf1b7fc464a9e85fcec450dddf80816b76e0
RUN set -x \
    && git clone https://github.com/akavel/rsrc.git /go/src/github.com/akavel/rsrc \
    && cd /go/src/github.com/akavel/rsrc \
    && git checkout -q $RSRC_COMMIT \
    && go install -v

# Wrap all commands in the "docker-in-docker" script to allow nested containers
ENTRYPOINT ["hack/dind"]

# Upload docker source
COPY . /go/src/github.com/docker/docker
