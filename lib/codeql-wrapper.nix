# CodeQL wrapper function for Nix packages
# Wraps the build phase with CodeQL database creation.
# Database is stored in separate 'codeql' output: result-codeql/
#
# Strategy: Use preBuild hook to intercept before the actual build runs.
# At that point, setup-hooks have set $buildPhase (e.g., "ninjaBuildPhase").
# We save the environment, and run the build under CodeQL tracing.
#
# NOTE: CodeQL databases are NOT byte-for-byte reproducible due to:
# - Embedded timestamps in database metadata
# - GCC temporary file names (ccXXXXXX.s) in string pools
# - Compilation timing data
# However, query results will be semantically identical between builds.
#
# Usage:
#   wrapWithCodeql = import ./lib/codeql-wrapper.nix { inherit pkgs; };
#   myPkg-codeql = wrapWithCodeql pkgs.hello;

{ pkgs }:

pkg:
pkg.overrideAttrs (old: {
  pname = "${old.pname or old.name}-codeql";

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    pkgs.codeql
    pkgs.unzip
  ];

  outputs = (old.outputs or [ "out" ]) ++ [ "codeql" ];

  # Use preBuild to intercept before the actual build runs
  preBuild = ''
    # Guard against recursive invocation
    if [[ -n "''${_CODEQL_WRAPPER_ACTIVE:-}" ]]; then
      return 0 2>/dev/null || true
    fi
    export _CODEQL_WRAPPER_ACTIVE=1
  ''
  + (old.preBuild or "")
  + ''
    echo "CodeQL wrapper: Creating database at $codeql"

    # Save environment and functions to a file that the subprocess can source
    _codeql_env_file="$(pwd)/.codeql-env.sh"
    _codeql_build_script="$(pwd)/.codeql-build.sh"

    # Export ALL variables and functions, filtering out readonly ones
    {
      echo "set +u"
      declare -p | grep -v '^declare -[^- ]*r' || true
      echo ""
      declare -f
      echo "set -u"
    } > "$_codeql_env_file"

    # Create build script that sources the environment and calls buildPhase
    cat > "$_codeql_build_script" << BUILDSCRIPT
    #!${pkgs.bash}/bin/bash
    set -eu
    set -o pipefail

    # Source the saved environment
    source "\$1"

    # Change to the build directory
    cd "\$2"

    runPhase buildPhase
    BUILDSCRIPT

    chmod +x "$_codeql_build_script"

    # Run the build under CodeQL tracing
    _codeql_raw="$(pwd)/.codeql-db-raw"

    codeql database create "$_codeql_raw" \
      --language=cpp \
      --command="$_codeql_build_script $_codeql_env_file $(pwd)"

    rm -f "$_codeql_env_file" "$_codeql_build_script"

    # Bundle the database with only essential query-relevant data
    # This strips logs, diagnostics, and cache that aren't needed for queries
    echo "CodeQL wrapper: Bundling database..."

    _codeql_bundle="$(pwd)/.codeql-bundle.zip"
    codeql database bundle "$_codeql_raw" \
      --output="$_codeql_bundle" \
      --no-include-diagnostics \
      --no-include-logs \
      --cache-cleanup=clear \
      --cleanup-upgrade-backups

    # Extract the bundle to the final output
    _codeql_extracted="$(pwd)/.codeql-extracted"
    ${pkgs.unzip}/bin/unzip -q "$_codeql_bundle" -d "$_codeql_extracted"

    mkdir -p "$codeql"
    _nested_dir=$(find "$_codeql_extracted" -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [[ -n "$_nested_dir" ]]; then
      mv "$_nested_dir"/* "$codeql/"
    else
      mv "$_codeql_extracted"/* "$codeql/"
    fi

    rm -rf "$_codeql_raw" "$_codeql_bundle" "$_codeql_extracted"
    echo "CodeQL wrapper: Database created successfully"
  '';

  # Guard postBuild with a file flag since env vars don't propagate from CodeQL subprocess
  postBuild = ''
    if [[ -f "$(pwd)/.codeql-postbuild-done" ]]; then
      rm -f "$(pwd)/.codeql-postbuild-done"
      return 0 2>/dev/null || true
    fi
    touch "$(pwd)/.codeql-postbuild-done"
  ''
  + (old.postBuild or "");

  # Skip tests - we only care about the build for CodeQL analysis
  doCheck = false;
  doInstallCheck = false;

  meta = (old.meta or { }) // {
    outputsToInstall = (old.meta.outputsToInstall or [ "out" ]) ++ [ "codeql" ];
  };
})
