#!/usr/bin/env bash

set -ueo pipefail

. $(dirname "${BASH_SOURCE[0]}")/common.sh

log "Dub     : $(dub --version | head -n1)"
log "System  : $(uname -a)"
echo

TESTSUITE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SOMETHING_FAILED=0

for test in $(ls -vd $TESTSUITE/*/); do
	log Performing test $(basename $test)...
	
	if TESTSUITE=$TESTSUITE ${test}test.sh; then
		true
	else
		SOMETHING_FAILED=1
		logError "Command failed"
	fi
done

exit ${SOMETHING_FAILED:-0}