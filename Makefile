.PHONY: test lint
test:
	bats test/
lint:
	shellcheck -x lib/*.sh core/*.sh modules/*.sh payload/hooks/*.sh install.sh VERIFY.sh
