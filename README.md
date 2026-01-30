# CodeQL Build Wrapper for Nix

A Nix flake that wraps package builds with CodeQL database creation for C/C++ static analysis research. Uses Nix for reproducibility and provides both declarative and imperative workflows.

## Quick Start

```bash
# Enter development shell (includes patched CodeQL)
nix develop

# Build a package with CodeQL database (declarative)
nix build .#hello-codeql

# The binary is at result/bin/*, database at result-codeql/
./result/bin/hello
ls result-codeql/

# Run queries against the database
./scripts/run-query result-codeql queries/list-functions.ql
./scripts/run-query result-codeql queries/unsafe-functions.ql
./scripts/run-query result-codeql queries/database-stats.ql
```

## Features

- **Automatic CodeQL database creation** during package builds
- **Declarative workflow** via flake outputs for verified packages
- **Imperative workflow** for testing arbitrary packages without flake modification
- **Reproducible** builds using Nix flakes (nixpkgs 25.11)
- **Patched CodeQL** for NixOS compatibility
- **Sample queries** for verification and analysis
- **Helper scripts** for database creation and query execution

## Architecture

### Core Components

- **[flake.nix](flake.nix)** — Main entry point; pins nixpkgs 25.11, defines CodeQL overlay, wrapper function, and package exports
- **[lib/codeql-wrapper.nix](lib/codeql-wrapper.nix)** — Core wrapper function that intercepts build phase and creates CodeQL database
- **[queries/](queries/)** — CodeQL queries and pack metadata:
  - [qlpack.yml](queries/qlpack.yml) — CodeQL pack metadata (depends on `codeql/cpp-all`)
  - [list-functions.ql](queries/list-functions.ql) — Lists all functions with locations
  - [unsafe-functions.ql](queries/unsafe-functions.ql) — Finds potentially unsafe C function calls
  - [database-stats.ql](queries/database-stats.ql) — Shows database statistics
- **[scripts/](scripts/)** — Helper scripts:
  - [wrap-package](scripts/wrap-package) — Imperative wrapper for testing packages
  - [run-query](scripts/run-query) — Run queries against databases
- **[packages/](packages/)** — Local test packages (e.g., `hello-c/`)

### How It Works

The wrapper uses the `preBuild` hook to intercept the build before it executes. It:
1. Saves the build environment (variables and functions)
2. Runs the actual build under CodeQL tracing
3. Creates and bundles the CodeQL database
4. Stores the database in a separate `codeql` output

## Workflows

### Declarative (Stable Packages)

Add verified packages to `packagesToWrap` in [flake.nix](flake.nix), then build:

```bash
nix build .#hello-codeql
nix build .#git-codeql
nix build .#curl-codeql
```

### Imperative (Testing New Packages)

Test any nixpkgs package without modifying the flake:

```bash
# Test nixpkgs package
./scripts/wrap-package redis

# Test local package
./scripts/wrap-package --local ./packages/hello-c

# Custom output name
./scripts/wrap-package -o result-redis redis
```

### Running Queries

Use the helper script to run queries (automatically handles read-only database issues):

```bash
# Single query
./scripts/run-query result-codeql queries/list-functions.ql

# With output format
./scripts/run-query result-codeql queries/unsafe-functions.ql --format csv -o results.csv

# Run all queries in directory
./scripts/run-query result-codeql queries/
```

Or use CodeQL directly:

```bash
codeql query run --database result-codeql queries/list-functions.ql
```

## Configuration

### Changing CodeQL Version

Edit `codeqlVersion` in [flake.nix](flake.nix):

```nix
codeqlVersion = "2.24.0";  # or null for nixpkgs default
```

Then update the hash by running `nix build .#codeql` — it will fail and show the correct `sha256-...` hash. The flake uses **codeql-bundle** which includes all standard packs, so no `codeql pack install` is needed.

### Adding Packages

Edit the `packagesToWrap` list in [flake.nix](flake.nix):

```nix
packagesToWrap = [
  "hello"
  "git"
  "curl"
  # Add more here
];
```

Then build with:

```bash
nix build .#<package-name>-codeql
```

### CodeQL Overlay

The overlay patches `pkgs.codeql` with `autoPatchelfHook` to fix ELF issues on NixOS. Currently ignores:
- `libasound.so.2`
- `liblttng-ust.so.0`

If new libraries need ignoring, update the overlay in [flake.nix](flake.nix).

## Using the Wrapper in External Flakes

```nix
{
  inputs.codeql-wrapper.url = "github:you/codeql-build-wrapper";

  outputs = { self, nixpkgs, codeql-wrapper, ... }:
    let
      pkgs = import nixpkgs {
        overlays = [ codeql-wrapper.overlays.default ];
      };
      wrap = codeql-wrapper.lib.x86_64-linux.wrapWithCodeql;
    in {
      packages.myPkg-codeql = wrap pkgs.myPkg;
    };
}
```

## Development

```bash
# Enter development shell
nix develop

# Update dependencies
nix flake update

# Check flake validity
nix flake check

# Build local test package
nix build .#hello-c-codeql
```

## Common Commands

| Task | Command |
|------|---------|
| Enter dev shell | `nix develop` |
| Build wrapped package | `nix build .#<name>-codeql` |
| Wrap package imperatively | `./scripts/wrap-package <package-name>` |
| Run query | `./scripts/run-query result-codeql queries/<query>.ql` |
| Update flake inputs | `nix flake update` |
| Check flake validity | `nix flake check` |

## Notes

### Database Reproducibility

CodeQL databases are **not** byte-for-byte reproducible due to:
- Embedded timestamps in database metadata
- GCC temporary file names (`ccXXXXXX.s`) in string pools
- Compilation timing data

However, **query results are semantically identical** between builds of the same source.

### Database Location

After building a wrapped package:
- Binary: `result/bin/*`
- CodeQL Database: `result-codeql/`

The database is stored as a separate Nix output, accessible via the `codeql` output attribute.

## License

MIT
