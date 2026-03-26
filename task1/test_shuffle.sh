#!/usr/bin/env bash
# tests for shuffle.sh

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DIR}/shuffle.sh"
PASS=0
FAIL=0

pass() {
    PASS=$(( PASS + 1 ))
    printf "\033[0;32m  PASS\033[0m: %s\n" "$1"
}

fail() {
    FAIL=$(( FAIL + 1 ))
    printf "\033[0;31m  FAIL\033[0m: %s\n" "$1"
    [[ -n "${2:-}" ]] && printf "       -> %s\n" "$2"
}

get_output() {
    OUTPUT="$(bash "$SCRIPT")"
}

echo "running tests..."

# 1) should exit cleanly
echo ""
if bash "$SCRIPT" > /dev/null 2>&1; then
    pass "exit code is 0"
else
    fail "non-zero exit code"
fi

# 2) should print exactly 10 lines
echo ""
get_output
count="$(echo "$OUTPUT" | wc -l | tr -d '[:space:]')"
if [[ "$count" -eq 10 ]]; then
    pass "10 lines"
else
    fail "expected 10 lines got $count"
fi

# 3) should have all numbers 1-10
echo ""
get_output
sorted="$(echo "$OUTPUT" | sort -n)"
expected="$(printf '%s\n' {1..10})"
if [[ "$sorted" == "$expected" ]]; then
    pass "all numbers present"
else
    fail "missing numbers" "got: $(echo "$sorted" | tr '\n' ' ')"
fi

# 4) no dupes
echo ""
get_output
total="$(echo "$OUTPUT" | wc -l | tr -d '[:space:]')"
uniq="$(echo "$OUTPUT" | sort -u | wc -l | tr -d '[:space:]')"
if [[ "$uniq" -eq "$total" ]]; then
    pass "no duplicates"
else
    fail "duplicates found" "unique=$uniq total=$total"
fi

# 5) every line should be a number between 1 and 10
echo ""
get_output
valid=true
while IFS= read -r line; do
    if ! [[ "$line" =~ ^[0-9]+$ ]] || (( line < 1 || line > 10 )); then
        valid=false
        break
    fi
done <<< "$OUTPUT"
if $valid; then
    pass "all valid integers"
else
    fail "bad line: '$line'"
fi

# 6) should not give same result every time
echo ""
runs=()
for (( i = 0; i < 5; i++ )); do
    runs+=("$(bash "$SCRIPT" | tr '\n' ',')")
done
same=true
for (( i = 1; i < 5; i++ )); do
    if [[ "${runs[$i]}" != "${runs[0]}" ]]; then
        same=false
        break
    fi
done
if ! $same; then
    pass "output varies between runs"
else
    fail "same output 5 times in a row"
fi

# 7) nothing on stderr
echo ""
err="$(bash "$SCRIPT" 2>&1 >/dev/null)"
if [[ -z "$err" ]]; then
    pass "no stderr"
else
    fail "got stderr" "$err"
fi

echo ""
echo "done: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
