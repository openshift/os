.PHONY: syntax-check
syntax-check:
	@set -e; for jsonfile in $$(find . -name '*.json'); do \
		echo -n "Checking JSON syntax for $${jsonfile}... "; \
		jq < $${jsonfile} . >/dev/null; \
		echo "OK"; \
	done

.PHONY: container
container:
	imagebuild -privileged .

.PHONY: refresh
refresh:
	./generate-openshift-repo
