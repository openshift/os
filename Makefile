# Use for e.g. --cache-only
COMPOSEFLAGS ?=
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
CACHE_ARGS := $(shell if test -d cache; then echo $(shell pwd)/cache; fi)

REPO ?= /srv/rhcos/repo
INSTALLER_TREE_URL ?= https://download.fedoraproject.org/pub/fedora/linux/releases/28/Everything/x86_64/os/
OSTREE_INSTALL_URL ?= ${REPO}
REF ?= openshift/3.10/x86_64/os

all: rpmostree-compose

.PHONY: syntax-check
syntax-check:
	@set -e; for jsonfile in $$(find ${ROOT_DIR} -name '*.json'); do \
		echo -n "Checking JSON syntax for $${jsonfile}... "; \
		jq < $${jsonfile} . >/dev/null; \
		echo "OK"; \
	done
	@set -e; for yamlfile in $$(find ${ROOT_DIR} -name '*.yaml' -o -name '*.yml'); do \
		echo -n "Checking YAML syntax for $${yamlfile}... "; \
		python3 -c "import yaml; yaml.safe_load(open('$${yamlfile}'))"; \
		echo "OK"; \
	done

.PHONY: repo-refresh
repo-refresh:
	${ROOT_DIR}/generate-openshift-repo

.PHONY: init-ostree-repo
init-ostree-repo:
	ostree --repo=build-repo init --mode=bare-user
	ostree --repo=repo init --mode=archive

.PHONY: check-tools
check-tools:
	which ostree
	which rpm-ostree
	which rpmdistro-gitoverlay
	which imagefactory
	which qemu-img
	which mock


# Runs all targets needed to create an image
.PHONY: build-rhcos
build-rhcos: check-tools clean repo-refresh rdgo rpmostree-compose os-image

# Cleans up
.PHONY: clean
clean:
	rm -rf build build-0 build-1 src snapshot ${REPO}

# Pulls sources, builds packages, and creates a dnf repo for use
.PHONY: rdgo
rdgo:
	rpmdistro-gitoverlay init
	rpmdistro-gitoverlay resolve --fetch-all
	rpmdistro-gitoverlay build


# Composes an ostree
.PHONY: rpmostree-compose
rpmostree-compose: ${ROOT_DIR}/openshift.repo init-ostree-repo
	mkdir -p ${REPO}
	ostree init --repo=${REPO} --mode=archive
	if test -d cache; then cachedir='--cachedir $(shell pwd)/cache'; fi && \
	  cd ${ROOT_DIR} && set -x && \
	  rpm-ostree compose tree $(COMPOSEFLAGS) $${cachedir:-} --repo=$(shell pwd)/build-repo host-maipo.yaml
	ostree --repo=repo pull-local build-repo
	ostree --repo=repo summary -u

# Makes an image using the ostree
.PHONY: os-image
os-image:
	ostree --repo=repo remote add rhcos --no-gpg-verify ${OSTREE_INSTALL_URL}
	ostree --repo=repo pull --mirror --commit-metadata-only rhcos
	sed -i 's,@@OSTREE_INSTALL_URL@@,${OSTREE_INSTALL_URL},' cloud.ks
	sed -i 's,@@OSTREE_INSTALL_REF@@,${REF},' cloud.ks
	coreos-virt-install --dest rhcos-devel.qcow2 --create-disk --kickstart cloud.ks --location $(INSTALLER_TREE_URL)
