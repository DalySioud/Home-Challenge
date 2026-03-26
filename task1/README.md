# shuffle.sh

A bash script that prints the numbers 1 to 10 in random order. Each number shows up exactly once.

## Description

The script builds an array of numbers 1-10, then shuffles them using the Fisher-Yates algorithm
(also called Knuth shuffle). This is a well-known O(n) approach that gives unbiased
random permutation, where every possible ordering is equally likely.

I chose this approach instead of something simpler (like picking random numbers and skipping duplicates) because Fisher-Yates is guaranteed to finish in exactly n steps and doesn't waste cycles on
collisions.

No external tools like `shuf`, `sort -R`, or `awk` are used, it's pure bash.

## Build instructions

There's nothing to build. It's just a bash script.

**Requirements:** Bash 3.2 or newer (for arrays and `$RANDOM`).

```bash
# clone and enter the directory
git clone <repository-url>
cd Home-Challenge

# make scripts executable
chmod +x shuffle.sh test_shuffle.sh
```

On Linux/macOS bash is already there. On Windows you can use Git Bash or WSL.

## Usage

```bash
./shuffle.sh
```

Example output:

```
7
3
10
1
8
5
4
9
2
6
```

Every run gives a different order.

## Tests

The test script runs 7 checks against `shuffle.sh`:

```bash
./test_shuffle.sh
```

What it tests:
- Exit code is 0
- Exactly 10 lines of output
- All numbers 1-10 are present
- No duplicates
- Every line is a valid integer in the right range
- Output actually changes between runs (randomness smoke test)
- Nothing unexpected on stderr

## Known limitations / bugs

- **$RANDOM is only 15 bits (0-32767).** For shuffling 10 numbers this is fine, but if this is scaled to much larger ranges, modulo bias appears. Not an issue at this scale.

- **Not cryptographically secure.** $RANDOM is a simple PRNG seeded from PID and time.
  Don't use this for anything security-related. An option is to use `/dev/urandom` for that.

- **Bash-specific.** Won't work with `sh`, `dash`, or other POSIX-only shells since it depends on bash arrays and arithmetic.

- **Range is hardcoded.** The 1-10 range is written directly in the script. It would be possible to adjust the script to accept arguments like `./shuffle.sh 1 10`, this would make it generate other random ranges. In that case other tests need to be implemented. 

- **Fast repeated executions can produce similar random sequences.** Running the script many times in quick succession may result in similar outputs. This is a limitation of Bash’s PRNG, not the shuffle algorithm.

