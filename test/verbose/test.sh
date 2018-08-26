. $TESTSUITE/common.sh

OUTPUT=$(dub test --root=$(dirname "${BASH_SOURCE[0]}") --skip-registry=all --nodeps -q -- --no-colours --verbose 2>&1 || true)

echo "$OUTPUT" | grep -cE "✓ verbose 1 \(1000\.[0-9]{3} ms\)" > /dev/null
echo "$OUTPUT" | grep -cE "✓ verbose 2 \(500\.[0-9]{3} ms\)" > /dev/null
echo "$OUTPUT" | grep -cE "✓ verbose 3 \(250\.[0-9]{3} ms\)" > /dev/null
echo "$OUTPUT" | grep -cE "silly.d" > /dev/null
echo "$OUTPUT" | grep -c "Summary: 3 passed, 1 failed" > /dev/null

rm -r $(dirname "${BASH_SOURCE[0]}")/.dub $(dirname "${BASH_SOURCE[0]}")/verbose-test-unittest