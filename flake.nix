{
  description = "CodeQL build wrapper for Nix packages - creates CodeQL databases during build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      # ─────────────────────────────────────────────────────────────────
      # Configuration: CodeQL version and packages to wrap
      # ─────────────────────────────────────────────────────────────────

      # Override this to use a different CodeQL version
      # Set to null to use the nixpkgs default version
      codeqlVersion = "2.24.0"; # e.g., "2.24.0" or null

      # List of package attribute names to wrap with CodeQL
      # These will be available as: nix build .#hello-codeql, .#git-codeql, etc.
      #
      # NOTE: For testing new packages, use the imperative workflow instead:
      #   ./scripts/wrap-package <package-name>
      # Only add packages here once they are verified to work correctly.
      packagesToWrap = [
        "hello"
        "git"
        "curl"
        "apacheHttpd"
        "openssl"
        "protobuf"
        "scrcpy"
        "netdata"
        "redis"
        "ffmpeg_7-headless"
        "tmux"
        "wrk"
        "godot"
        "mpv-unwrapped"
        # Add more verified packages here
      ];

      # ─────────────────────────────────────────────────────────────────
      # CodeQL overlay: patches CodeQL for NixOS compatibility
      # ─────────────────────────────────────────────────────────────────

      codeqlOverlay = final: prev: {
        codeql = prev.codeql.overrideAttrs (
          old:
          {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              final.autoPatchelfHook
              final.unzip
            ];
            autoPatchelfIgnoreMissingDeps = [
              "libasound.so.2"
              "liblttng-ust.so.0"
            ];
          }
          // (
            if codeqlVersion != null then
              {
                # Override version + src when a specific version is requested
                # Using codeql-bundle which includes all standard packs (no need for codeql pack install)
                version = codeqlVersion;
                src = final.fetchurl {
                  url = "https://github.com/github/codeql-action/releases/download/codeql-bundle-v${codeqlVersion}/codeql-bundle-linux64.tar.gz";
                  # Users must update this hash when changing codeqlVersion
                  hash = "sha256-FkbYRuD226u9wQK0pisd86/YSH849iX+1Isn7UR9rjc=";
                };
              }
            else
              { }
          )
        );
      };

      # ─────────────────────────────────────────────────────────────────
      # Helper: generate wrapped packages from a list of attr names
      # ─────────────────────────────────────────────────────────────────

      mkWrappedPackages =
        pkgs: wrapFn: packageNames:
        builtins.listToAttrs (
          map (name: {
            name = "${name}-codeql";
            value = wrapFn pkgs.${name};
          }) packageNames
        );

    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ codeqlOverlay ];
        };

        # Import wrapper function from lib/
        wrapWithCodeql = import ./lib/codeql-wrapper.nix { inherit pkgs; };

        # Generate wrapped packages for the declared list
        wrappedPackages = mkWrappedPackages pkgs wrapWithCodeql packagesToWrap;

        # ─────────────────────────────────────────────────────────────────
        # Local packages from packages/ directory
        # ─────────────────────────────────────────────────────────────────

        # hello-c: our test C package
        hello-c = pkgs.callPackage ./packages/hello-c { };
      in
      {
        # ─────────────────────────────────────────────────────────────────
        # legacyPackages: expose pkgs for imperative use
        # This allows: nix build --impure --expr 'let flake = ...; in ...'
        # Used by: ./scripts/wrap-package
        # ─────────────────────────────────────────────────────────────────

        legacyPackages = pkgs;

        # ─────────────────────────────────────────────────────────────────
        # Packages: declarative package outputs (stable)
        # ─────────────────────────────────────────────────────────────────

        packages = wrappedPackages // {
          # Expose the patched codeql itself
          codeql = pkgs.codeql;

          # Local packages (CodeQL-wrapped build)
          hello-c-codeql = wrapWithCodeql hello-c;

          # Default package (for nix build)
          default = wrapWithCodeql hello-c;
        };

        # ─────────────────────────────────────────────────────────────────
        # DevShell: development environment with CodeQL
        # ─────────────────────────────────────────────────────────────────

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.codeql ];

          shellHook = ''
            echo "╔═══════════════════════════════════════════════════════════╗"
            echo "║       CodeQL Build Wrapper - Development Shell            ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║ CodeQL: $(codeql --version | head -n 1 | cut -d' ' -f3)   Nixpkgs: 25.11"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║ Declarative (stable packages in flake.nix):               ║"
            echo "║   nix build .#hello-codeql                                ║"
            echo "║   nix build .#hello-c-codeql                              ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║ Imperative (test any package without modifying flake):    ║"
            echo "║   ./scripts/wrap-package curl                             ║"
            echo "║   ./scripts/wrap-package --local ./packages/hello-c       ║"
            echo "╠═══════════════════════════════════════════════════════════╣"
            echo "║ Run queries:                                               ║"
            echo "║   ./scripts/run-query result-codeql queries/list-functions.ql"
            echo "║   ./scripts/run-query result-codeql queries/unsafe-functions.ql"
            echo "╚═══════════════════════════════════════════════════════════╝"
          '';
        };

        # ─────────────────────────────────────────────────────────────────
        # Lib: expose the wrapper function for external use
        # ─────────────────────────────────────────────────────────────────

        lib = {
          inherit wrapWithCodeql;
          mkWrappedPackages = mkWrappedPackages pkgs wrapWithCodeql;
        };
      }
    )
    // {
      # ─────────────────────────────────────────────────────────────────
      # Overlays: can be used by other flakes
      # ─────────────────────────────────────────────────────────────────

      overlays.default = codeqlOverlay;
      overlays.codeql = codeqlOverlay;
    };
}
