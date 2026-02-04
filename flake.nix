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
      # Configuration: supported systems and packages to wrap
      # ─────────────────────────────────────────────────────────────────

      codeqlVersion = "2.24.0";
      codeqlReleaseUrl = "https://github.com/github/codeql-action/releases/download/codeql-bundle-v${codeqlVersion}";
      codeqlBundles = {
        "x86_64-linux" = {
          filename = "codeql-bundle-linux64.tar.gz";
          hash = "sha256-FkbYRuD226u9wQK0pisd86/YSH849iX+1Isn7UR9rjc=";
        };
        "aarch64-darwin" = {
          filename = "codeql-bundle-osx64.tar.gz";
          hash = "sha256-0D7ur1QElPYyb6FTft9U7cBFwBp+6MXN4hxm2vT2vKM=";
        };
      };

      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

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

      codeqlBundleForSystem =
        system:
        let
          bundle = codeqlBundles.${system} or null;
        in
        if bundle == null then
          throw "Unsupported system for CodeQL bundle: '${system}'. Supported systems: ${builtins.concatStringsSep ", " (builtins.attrNames codeqlBundles)}"
        else
          bundle // { url = "${codeqlReleaseUrl}/${bundle.filename}"; };

      codeqlOverlay = final: prev: {
        codeql = prev.codeql.overrideAttrs (
          old:
          let
            bundleForSystem = codeqlBundleForSystem final.stdenv.hostPlatform.system;
            codeqlSrc = final.fetchurl {
              url = bundleForSystem.url;
              hash = bundleForSystem.hash;
            };

            # Install phase for macOS: extract bundle and link Java
            darwinInstallPhase = ''
              # codeql directory should not be top-level, otherwise,
              # it'll include /nix/store to resolve extractors.
              mkdir -p $out/{codeql,bin}
              cp -R * $out/codeql/

              # Ensure CODEQL_DIST + CODEQL_PLATFORM resolve a usable Java
              if [ -d "$out/codeql/tools/osx64/java" ]; then
                rm -rf $out/codeql/tools/osx64/java
                ln -s ${final.jdk17} $out/codeql/tools/osx64/java
              fi

              # On Apple Silicon, the bundle also contains java-aarch64
              if [ -d "$out/codeql/tools/osx64/java-aarch64" ]; then
                rm -rf $out/codeql/tools/osx64/java-aarch64
                ln -s ${final.jdk17} $out/codeql/tools/osx64/java-aarch64
              fi

              ln -s $out/codeql/codeql $out/bin/
            '';
          in
          {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              final.autoPatchelfHook
              final.unzip
            ];
            dontAutoPatchelf = final.stdenv.hostPlatform.isDarwin;
            autoPatchelfIgnoreMissingDeps = [
              "libasound.so.2"
              "liblttng-ust.so.0"
            ];
            installPhase =
              if final.stdenv.hostPlatform.isDarwin then darwinInstallPhase else (old.installPhase or "");
          }
          // {
            # Use fetchurl to download CodeQL bundle on-demand for the current system
            src = codeqlSrc;
            version = codeqlVersion;
          }
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
    flake-utils.lib.eachSystem supportedSystems (
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
