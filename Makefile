HOME=$(shell pwd)
MAINVERSION?=2.8
LUA_VERSION=5.4.7
USE_LUA?=0
USE_PROMETHEUS?=0
VERSION=$(shell curl -sL https://git.haproxy.org/git/haproxy-${MAINVERSION}.git/refs/tags/ | sed -n 's:.*>\(.*\)</a>.*:\1:p' | sed 's/^.//' | sort -rV | head -1)
ifeq ("${VERSION}","./")
	VERSION="${MAINVERSION}.0"
endif
RELEASE=1

all: build

install_prereq:
	yum install -y pcre-devel make gcc openssl-devel rpm-build systemd-devel zlib-devel

clean:
	rm -f ./SOURCES/haproxy-${VERSION}.tar.gz
	rm -rf ./rpmbuild
	mkdir -p ./rpmbuild/SPECS/ ./rpmbuild/SOURCES/ ./rpmbuild/RPMS/ ./rpmbuild/SRPMS/
	rm -rf ./lua-${LUA_VERSION}*

download-upstream:
	curl -sL https://www.haproxy.org/download/${MAINVERSION}/src/haproxy-${VERSION}.tar.gz -o ./SOURCES/haproxy-${VERSION}.tar.gz

build_lua:
	yum install -y readline-devel
	curl -sOL https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz
	tar xzf lua-${LUA_VERSION}.tar.gz
	cd lua-${LUA_VERSION}
	$(MAKE) -C lua-${LUA_VERSION} clean
	$(MAKE) -C lua-${LUA_VERSION} MYCFLAGS=-fPIC linux test  # MYCFLAGS=-fPIC is required during linux ld
	$(MAKE) -C lua-${LUA_VERSION} install

build_stages := install_prereq clean download-upstream
ifeq ($(USE_LUA),1)
	build_stages += build_lua
endif

build-docker:
	docker build -t haproxy-rpm-builder:latest -f Dockerfile .

run-docker: build-docker
	mkdir -p RPMS
ifeq ($(USE_LUA),1)
	docker run -e USE_LUA=${USE_LUA} -e USE_PROMETHEUS=${USE_PROMETHEUS} -e RELEASE=${RELEASE} --volume $(HOME)/RPMS:/RPMS --rm haproxy-rpm-builder:latest
else
	docker run -e USE_PROMETHEUS=${USE_PROMETHEUS} -e RELEASE=${RELEASE} --volume $(HOME)/RPMS:/RPMS --rm haproxy-rpm-builder:latest
endif

build: $(build_stages)
	cp -r ./SPECS/* ./rpmbuild/SPECS/ || true
	cp -r ./SOURCES/* ./rpmbuild/SOURCES/ || true
	rpmbuild -ba SPECS/haproxy.spec \
	--define "mainversion ${MAINVERSION}" \
	--define "version ${VERSION}" \
	--define "release ${RELEASE}" \
	--define "_topdir %(pwd)/rpmbuild" \
	--define "_builddir %{_topdir}/BUILD" \
	--define "_buildroot %{_topdir}/BUILDROOT" \
	--define "_rpmdir %{_topdir}/RPMS" \
	--define "_srcrpmdir %{_topdir}/SRPMS" \
	--define "_use_lua ${USE_LUA}" \
	--define "_use_prometheus ${USE_PROMETHEUS}"
