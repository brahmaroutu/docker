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

FROM gccgo-image       
MAINTAINER	Tianon Gravi <admwiggin@gmail.com> (@tianon)

RUN echo "deb http://ftp.de.debian.org/debian wheezy-backports main " >> /etc/apt/sources.list

# Packaged dependencies
RUN	apt-get update && apt-get install -y \
	aufs-tools \
	automake \
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
	ruby1.9.1 \
	ruby1.9.1-dev \
	s3cmd=1.1.0* \
	--no-install-recommends

# Get lvm2 source for compiling statically
RUN	git clone --no-checkout git://git.fedorahosted.org/git/lvm2.git /usr/local/lvm2 && cd /usr/local/lvm2 && git checkout -q v2_02_103
# see https://git.fedorahosted.org/cgit/lvm2.git/refs/tags for release tags
# note: we don't use "git clone -b" above because it then spews big nasty warnings about 'detached HEAD' state that we can't silence as easily as we can silence them using "git checkout" directly
RUN    curl -o /usr/local/lvm2/autoconf/config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
RUN    curl -o /usr/local/lvm2/autoconf/config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'

# Compile and install lvm2
RUN	cd /usr/local/lvm2 && ./configure --enable-static_link && make device-mapper && make install_device-mapper
# see https://git.fedorahosted.org/cgit/lvm2.git/tree/INSTALL

# Install Go
#RUN	curl -sSL https://golang.org/dl/go1.3.3.src.tar.gz | tar -v -C /usr/local -xz
#ENV	PATH	/usr/local/go/bin:$PATH
ENV GO_VERSION 1.4.1
ENV	GOPATH	/go:/go/src/github.com/docker/docker/vendor
#ENV PATH /go/bin:$PATH
#RUN	cd /usr/local/go/src && ./make.bash --no-clean 2>&1

# Compile Go for cross compilation
#ENV	DOCKER_CROSSPLATFORMS	\
#	linux/386 linux/arm \
#	darwin/amd64 darwin/386 \
#	freebsd/amd64 freebsd/386 freebsd/arm \
#	windows/amd64 windows/386

# (set an explicit GOARM of 5 for maximum compatibility)
#ENV	GOARM	5
#RUN	cd /usr/local/go/src && bash -xc 'for platform in $DOCKER_CROSSPLATFORMS; do GOOS=${platform%/*} GOARCH=${platform##*/} ./make.bash --no-clean 2>&1; done'

# We still support compiling with older Go, so need to grab older "gofmt"
#ENV GOFMT_VERSION 1.4
#RUN curl -sSL https://storage.googleapis.com/golang/go${GOFMT_VERSION}.$(go env GOOS)-$(go env GOARCH).tar.gz | tar -C /go/bin -xz --strip-components=2 go/bin/gofmt

#RUN go clean -i net && go install -tags netgo std

# Grab Go's cover tool for dead-simple code coverage testing
RUN	go get golang.org/x/tools/cmd/cover

# TODO replace FPM with some very minimal debhelper stuff
RUN    apt-get install -y libffi-dev
RUN	gem install --no-rdoc --no-ri fpm --version 1.3.2

RUN     git clone -b docker-test-image-`uname -m` https://github.com/brahmaroutu/power_docker_image.git /docker-test-image
RUN     mkdir -p /var/lib/docker && tar -C /var/lib/docker -xf /docker-test-image/unit-tests.tar

# Get the "busybox" image source so we can build locally instead of pulling
RUN     git clone -b docker-busybox-`uname -m` https://github.com/brahmaroutu/power_docker_busybox.git /docker-busybox

# Get the "cirros" image source so we can import it instead of fetching it during tests
RUN	curl -sSL -o /cirros.tar.gz https://github.com/ewindisch/docker-cirros/raw/1cded459668e8b9dbf4ef976c94c05add9bbd8e9/cirros-0.3.0-x86_64-lxc.tar.gz

# Setup s3cmd config
RUN	/bin/echo -e '[default]\naccess_key=$AWS_ACCESS_KEY\nsecret_key=$AWS_SECRET_KEY' > $HOME/.s3cfg

# Set user.email so crosbymichael's in-container merge commits go smoothly
RUN	git config --global user.email 'docker-dummy@example.com'

# Add an unprivileged user to be used for tests which need it
RUN groupadd -r docker
RUN useradd --create-home --gid docker unprivilegeduser

VOLUME	/var/lib/docker
WORKDIR	/go/src/github.com/docker/docker
ENV	DOCKER_BUILDTAGS	apparmor selinux btrfs_noversion

# Install man page generator
COPY vendor /go/src/github.com/docker/docker/vendor
# (copy vendor/ because go-md2man needs golang.org/x/net)
RUN set -x \
	&& git clone -b v1 https://github.com/cpuguy83/go-md2man.git /go/src/github.com/cpuguy83/go-md2man \
	&& git clone -b v1.2 https://github.com/russross/blackfriday.git /go/src/github.com/russross/blackfriday \
	&& go install -v github.com/cpuguy83/go-md2man

# Install registry
#COPY pkg/tarsum /go/src/github.com/docker/docker/pkg/tarsum
# REGISTRY_COMMIT gives us the repeatability guarantees we need
# (so that we're all testing the same version of the registry)
#ENV REGISTRY_COMMIT 21a69f53b5c7986b831f33849d551cd59ec8cbd1
#RUN set -x \
#	&& git clone https://github.com/docker/distribution.git /go/src/github.com/docker/distribution \
#	&& (cd /go/src/github.com/docker/distribution && git checkout -q $REGISTRY_COMMIT) \
#	&& go get -d github.com/docker/distribution/cmd/registry \
#	&& go build -o /go/bin/registry-v2 github.com/docker/distribution/cmd/registry

# Wrap all commands in the "docker-in-docker" script to allow nested containers
ENTRYPOINT	["hack/dind"]

ENV CGO_ENABLED 1
ENV USE_GCCGO 1

# Upload docker source
COPY	.	/go/src/github.com/docker/docker
