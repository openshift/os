OS_FLAVOR ?= origin
# Use for e.g. --cache-only
COMPOSEFLAGS ?=
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
CACHE_ARGS := $(shell if test -d cache; then echo $(shell pwd)/cache; fi)
CONTAINER_NAME ?= $(OS_FLAVOR)-os

all: rpmostree-compose

.PHONY: syntax-check
syntax-check:
	@set -e; for jsonfile in $$(find ${ROOT_DIR} -name '*.json'); do \
		echo -n "Checking JSON syntax for $${jsonfile}... "; \
		jq < $${jsonfile} . >/dev/null; \
		echo "OK"; \
	done

.PHONY: container
container: repo-refresh
	imagebuilder -t $(CONTAINER_NAME) -privileged ${ROOT_DIR}

.PHONY: repo-refresh
repo-refresh:
	${ROOT_DIR}/generate-openshift-repo

.PHONY: init-ostree-repo
init-ostree-repo:
	ostree --repo=build-repo init --mode=bare-user
	ostree --repo=repo init --mode=archive

.PHONY: rpmostree-compose
rpmostree-compose: ${ROOT_DIR}/openshift.repo init-ostree-repo
	if test -d cache; then cachedir='--cachedir $(shell pwd)/cache'; fi && \
	  cd ${ROOT_DIR} && set -x && \
	  rpm-ostree $(COMPOSEFLAGS) compose tree $${cachedir:-} --repo=$(shell pwd)/build-repo host-$(OS_FLAVOR).json
	ostree --repo=repo pull-local build-repo
	ostree --repo=repo summary -u
