# CodeQL Build Wrapper for Nix

Purpose
-------
This repo wraps Nix package builds with CodeQL database creation for C/C++ static analysis research. It uses Nix flakes for reproducibility.

## Quick Start

```bash
# Enter development shell (has patched CodeQL)
nix develop

# Build a package with CodeQL database
nix build .#hello-codeql

# The database is at result-codeql/
codeql query run --database result-codeql queries/list-functions.ql
```

## Architecture

- **`flake.nix`** — Main entry point; pins nixpkgs 25.11, defines CodeQL overlay, wrapper function, and exports
- **`lib/codeql-wrapper.nix`** — Core wrapper function that intercepts build and creates CodeQL database
- **`queries/`** — CodeQL queries and pack metadata:
  - `qlpack.yml` — CodeQL pack metadata (depends on `codeql/cpp-all`)
  - `list-functions.ql` — Lists all functions with locations
  - `unsafe-functions.ql` — Finds potentially unsafe C function calls
  - `database-stats.ql` — Shows database statistics
- **`scripts/`** — Helper scripts:
  - `wrap-package` — Imperative wrapper for testing packages
  - `run-query` — Run queries against databases
- **`packages/`** — Local test packages (e.g., `hello-c/`)

## Key Patterns

### Adding Packages to Wrap

Edit `packagesToWrap` list in `flake.nix`:

```nix
packagesToWrap = [
  "hello"
  "git"
  "curl"
];
```

Then build with `nix build .#git-codeql`, etc.

### Changing CodeQL Version

Set `codeqlVersion` in `flake.nix`:

```nix
codeqlVersion = "2.16.0";  # or null for nixpkgs default
```

Then update the hash by running `nix build .#codeql` — it will fail and show the correct `sha256-...` hash. The flake uses **codeql-bundle** which includes all standard packs, so no `codeql pack install` is needed.

### Using the Wrapper Function Externally

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

### CodeQL Overlay

The overlay patches `pkgs.codeql` with `autoPatchelfHook` to fix ELF issues on NixOS. Libraries ignored:
- `libasound.so.2`
- `liblttng-ust.so.0`

Update both the overlay in `flake.nix` if new libs need ignoring.

## Workflows

| Task | Command |
|------|---------|
| Enter dev shell | `nix develop` |
| Build wrapped package | `nix build .#<name>-codeql` |
| Wrap package imperatively | `./scripts/wrap-package <package-name>` |
| Run query | `./scripts/run-query result-codeql queries/<query>.ql` |
| Update flake inputs | `nix flake update` |
| Check flake validity | `nix flake check` |