refresh:
	curl -q "https://storage.googleapis.com/origin-ci-test/releases/openshift/origin/master/origin.repo" 2>/dev/null >openshift.repo
.PHONY: refresh