.PHONY: syntax-check
syntax-check:
	@set -e; for jsonfile in $$(find . -name '*.json'); do \
		echo -n "Checking JSON syntax for $${jsonfile}... "; \
		jq < $${jsonfile} . >/dev/null; \
		echo "OK"; \
	done

.PHONY: container
container: repo-refresh
	imagebuild -privileged .

.PHONY: repo-refresh
repo-refresh:
	./generate-openshift-repo
