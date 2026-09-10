{
  description = "opi base development flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          toolsMetadata = builtins.fromJSON (builtins.readFile ./tools.json);

          resolvePkgs = names: map (name: pkgs.${name}) names;

          buildTool = name: metadata:
            pkgs.rustPlatform.buildRustPackage {
              pname = name;
              version = metadata.version;
              src = pkgs.fetchFromGitHub {
                inherit (metadata) owner repo;
                rev = "${metadata.tag_prefix}${metadata.version}";
                hash = metadata.hash;
              };
              cargoHash = metadata.cargo_hash;
              buildFeatures = metadata.build_features or [];
              nativeBuildInputs = resolvePkgs (metadata.native_build_inputs or []);
              buildInputs = resolvePkgs (metadata.build_inputs or []);
              doCheck = metadata.do_check or true;
            };

          tools = pkgs.lib.mapAttrs buildTool toolsMetadata;

          rPackages = [ ];

          systemDependencies = with pkgs; [
            # Generic source-build tooling
            gcc
            gnumake
            cmake
            pkg-config

            # Rust toolchain (ojoutils has Rust extensions)
            cargo
            rustc

            # Common native libs requested by R packages
            curl
            openssl
            libxml2
            libyaml
            zlib
            bzip2
            xz
            pcre2
            icu
            libgit2
            libuv

            # Database
            postgresql

            # Graphics / fonts
            fontconfig
            freetype
            harfbuzz
            fribidi
            cairo
            libpng
            libtiff
            libjpeg
            libwebp

            # Arrow C++ libs (ojoutils depends on arrow)
            arrow-cpp

            # Abseil C++ libs (s2, an sf hard dependency, links against
            # them when built from source)
            abseil-cpp

            # SQLite (terra's configure test-links sqlite3 for proj)
            sqlite

            # UDUNITS-2 (units, an sf hard dependency, links against it)
            udunits

            # DuckDB C++ lib (ojodb can use duckdb; matching the CRAN R package
            # version lets it link against the system library instead of compiling
            # DuckDB from source, which takes ~20 minutes).
            duckdb

            R
          ];

          rTools = [
            tools.rv
            tools.arf
            tools.jarl
            tools.air
          ];

          devShellTools = [
            pkgs.git
            pkgs.gh
            pkgs.google-cloud-sdk
          ];

          fonts = with pkgs; [
            source-sans
          ];

          fontsConf = pkgs.makeFontsConf { fontDirectories = fonts; };

          rWrapper = pkgs.rWrapper.override {
            packages = rPackages;
          };

          # Nix gcc-wrapper uses platform-specific NIX_LDFLAGS_* variables to inject
          # rpath/runpath flags. We reproduce what stdenv.mkDerivation does for buildInputs
          # so rv source builds embed Nix library paths in their .so files.
          hostConfig = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
          rpathFlags = pkgs.lib.concatMapStringsSep " " (
            pkg: "-rpath ${pkgs.lib.getLib pkg}/lib"
          ) systemDependencies;

          # Env vars exported to every opi shell. Downstream shells (opi module)
          # forward this whole set, so adding a variable here propagates to all
          # projects automatically. `env` makes them real env vars in the base shell;
          # `passthru` lets project shells read the set at eval time.
          pkgconfigDirs = pkgs.lib.concatMapStringsSep ":" (
            pkg: "${pkgs.lib.getDev pkg}/lib/pkgconfig"
          ) systemDependencies;

          # The nixpkgs pkg-config wrapper replaces PKG_CONFIG_PATH with a
          # role-suffixed var (PKG_CONFIG_PATH_<host>) built from the roles
          # registered via NIX_PKG_CONFIG_WRAPPER_TARGET_* vars. In devshells
          # built around R's cross-target wrapper environment only the
          # _FOR_TARGET role registers, so the plain PKG_CONFIG_PATH (which
          # build scripts like s2 append to at configure time) is silently
          # dropped. Registering the host role makes the wrapper's own
          # pipeline carry the plain path through. hostRole and hostConfig
          # are the same mangling; keep both spellings for readability of
          # each consumer (role vars vs gcc-wrapper vars).
          hostRole = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;

          shellEnv = {
            R_HOME = "${pkgs.R}/lib/R";
            FONTCONFIG_FILE = fontsConf;

            # Source-built R packages use pkg-config to find system libs
            # (gdal, abseil for s2, etc.). Point at every dependency's dev
            # pkgconfig dir; missing dirs in the list are harmless.
            PKG_CONFIG_PATH = pkgconfigDirs;

            # Register the pkg-config wrapper's host role (see above).
            "NIX_PKG_CONFIG_WRAPPER_TARGET_HOST_${hostRole}" = "1";
          };

          # Setup run in every opi shell. Passed through at eval time so
          # downstream shells (opi module) can prepend it to their own hooks.
          shellHook = ''
            echo "opi base shell ready."
            echo "R: $(which R)"
            echo "R_HOME: $R_HOME"
            echo "rv: $(rv --version)"
            echo "air: $(air --version)"
            echo "arf: $(arf --version)"
            echo "jarl: $(jarl --version)"

            # Embed Nix native library paths into source-built R packages via the
            # Nix gcc wrapper. This avoids needing LD_LIBRARY_PATH, which would
            # force system binaries (git, timedatectl, etc.) to load Nix glibc and
            # break on conventional Linux/macOS distributions.
            export NIX_LDFLAGS_${hostConfig}="${rpathFlags}"

            # Let rv manage project-local R packages without touching the Nix R library
            export R_LIBS_SITE="$PWD/rv/library"
            export R_LIBS_USER="$PWD/rv/library"
            mkdir -p "$R_LIBS_USER"

            # Prevent ~/.Renviron from overriding project library paths
            if [ -f "$PWD/.Renviron" ]; then
              export R_ENVIRON_USER="$PWD/.Renviron"
            else
              export R_ENVIRON_USER="/dev/null"
            fi
          '';
        in
        {
          devShells.default = pkgs.mkShell {
            name = "opi-base-shell";

            buildInputs = rPackages ++ systemDependencies;

            packages = [ rWrapper ] ++ rTools ++ devShellTools;

            env = shellEnv;

            passthru = {
              inherit shellEnv shellHook;
            };

            inherit shellHook;
          };
        };
    };
}
