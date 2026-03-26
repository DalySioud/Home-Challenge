#!/usr/bin/env bash
# shuffle.sh - prints numbers 1 to 10 in random order, no repeats

set -euo pipefail

main() {
    local -a nums
    local i j tmp

    for (( i = 1; i <= 10; i++ )); do
        nums+=("$i")
    done

    # fisher-yates shuffle
    for (( i = ${#nums[@]} - 1; i > 0; i-- )); do
        j=$(( RANDOM % (i + 1) ))
        # swap
        tmp=${nums[$i]}
        nums[$i]=${nums[$j]}
        nums[$j]=$tmp
    done

    for val in "${nums[@]}"; do
        echo "$val"
    done
}

main
