# hello-c

A simple C program for testing the CodeQL build wrapper.

## Features

- Basic "Hello, World!" functionality
- Includes both safe and unsafe string operations (for CodeQL to analyze)
- Standard Makefile-based build

## Building

### Normal build
```bash
nix build .#hello-c
./result/bin/hello-c
./result/bin/hello-c "Your Name"
```

### CodeQL-wrapped build
```bash
nix build .#hello-c-codeql
./result/bin/hello-c "Your Name"

# The CodeQL database is at:
ls result-codeql/

# Run queries against it:
../../scripts/run-query result-codeql ../../queries/list-functions.ql
../../scripts/run-query result-codeql ../../queries/unsafe-functions.ql
../../scripts/run-query result-codeql ../../queries/database-stats.ql
```

## Source Files

- `src/main.c` — Main program with greeting functions
- `Makefile` — Standard C build configuration
