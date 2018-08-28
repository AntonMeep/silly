. $TESTSUITE/common.sh

OUTPUT=$(dub test -b unittest-cov --root=$(dirname "${BASH_SOURCE[0]}") --skip-registry=all --nodeps -q -- --no-colours 2>&1)

echo "$OUTPUT" | grep -c "✓ .six.seven.eight.nine.ten.m name" > /dev/null
echo "$OUTPUT" | grep -c "Summary: 1 passed, 0 failed"        > /dev/null

EXEC=$(dirname "${BASH_SOURCE[0]}")/names-test-unittest

$EXEC --no-colours --verbose | grep -c "✓ names.one.two.three.four.five.six.seven.eight.nine.ten.m name" > /dev/null

rm -r $(dirname "${BASH_SOURCE[0]}")/.dub $(dirname "${BASH_SOURCE[0]}")/names-test-unittest