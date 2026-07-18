.PHONY: test lint
test:
	bats test/
lint:
	shellcheck -x lib/*.sh core/*.sh install.sh VERIFY.sh
