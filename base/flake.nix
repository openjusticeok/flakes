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

          # Quarto 1.9.x emits pandoc 3.8's `syntax-highlighting` defaults
          # field, but nixpkgs' pandoc (3.7.0.2) predates that rename
          # (nixpkgs#461018), so any render fails with
          # `Unknown option "syntax-highlighting"` (nixpkgs#519484).
          # 3.8.3 is the pandoc version quarto 1.9 bundles upstream
          # (quarto-dev/quarto-cli#13249). Drop once nixpkgs ships
          # pandoc >= 3.8.
          pandocForQuarto =
            let
              inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
              systemTag =
                if isDarwin then
                  (if isAarch64 then "arm64-macOS" else "x86_64-macOS")
                else if isAarch64 then "linux-arm64" else "linux-amd64";
              extension = if isDarwin then "zip" else "tar.gz";
              hash =
                if isDarwin then
                  (if isAarch64
                    then "sha256-Pq6zvRCYKuy6XddhWHRaT4Ba+zmrcqUZu6JTPJjOAC0="
                    else "sha256-ki41wCENfKIO6TJ4ETYdbX8O8K3aCJ4OdMs3VsPXE/k=")
                else
                  (if isAarch64
                    then "sha256-FmpaNzh+sQvUxPJCqBCb7vdVrB6NTrA5xrXr0dkY2Nc="
                    else "sha256-wiT6uJ+CfTYjOA7LfBB4wWPHachJoUrCfo07+7kUybQ=");
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = "pandoc";
              version = "3.8.3";
              src = pkgs.fetchurl {
                url = "https://github.com/jgm/pandoc/releases/download/3.8.3/pandoc-3.8.3-${systemTag}.${extension}";
                inherit hash;
              };
              nativeBuildInputs = [ pkgs.unzip ];
              # Only the binary is needed; quarto brings its own docs/tools.
              installPhase = ''
                mkdir -p $out/bin
                mv bin/pandoc $out/bin/pandoc
              '';
              meta.mainProgram = "pandoc";
            };

          # Quarto uses the shell's own R, discovered from PATH and pinned
          # explicitly via QUARTO_R in the shell hook. rWrapper is
          # deliberately null: it would bake nixpkgs rmarkdown into a
          # separate R instance and put an ELF wrapper shim in the shell
          # closure (the shim is a bare R front-end that tools like Positron
          # cannot parse). rmarkdown/knitr are rv-managed project deps via
          # rproject.toml instead. Typst PDF engine is bundled by nixpkgs
          # quarto; no LaTeX needed.
          quarto = pkgs.quarto.override {
            pandoc = pandocForQuarto;
            rWrapper = null;
          };

          devShellTools = [
            pkgs.git
            pkgs.gh
            pkgs.google-cloud-sdk
            quarto
          ];

          fonts = with pkgs; [
            source-sans
          ];

          fontsConf = pkgs.makeFontsConf { fontDirectories = fonts; };

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
            echo "quarto: $(quarto --version)"

            # Embed Nix native library paths into source-built R packages via the
            # Nix gcc wrapper. This avoids needing LD_LIBRARY_PATH, which would
            # force system binaries (git, timedatectl, etc.) to load Nix glibc and
            # break on conventional Linux/macOS distributions.
            export NIX_LDFLAGS_${hostConfig}="${rpathFlags}"

            # Let rv manage project-local R packages without touching the Nix R library.
            # Default to the plain rv/library path, then refine it to rv's real
            # versioned library (rv/library/<r_version>/<arch>/...) by asking rv
            # itself — needed by --vanilla sessions (callr, mirai/crew workers)
            # that skip .Rprofile activation entirely.
            export R_LIBS_SITE="$PWD/rv/library"
            export R_LIBS_USER="$PWD/rv/library"
            if [ -f rproject.toml ]; then
              rv_lib="$(rv info --library 2>/dev/null | sed -n 's/^library:[[:space:]]*//p')"
              if [ -n "$rv_lib" ]; then
                export R_LIBS_SITE="$PWD/$rv_lib"
                export R_LIBS_USER="$PWD/$rv_lib"
              fi
            fi
            mkdir -p "$R_LIBS_USER"

            # Prevent ~/.Renviron from overriding project library paths
            if [ -f "$PWD/.Renviron" ]; then
              export R_ENVIRON_USER="$PWD/.Renviron"
            else
              export R_ENVIRON_USER="/dev/null"
            fi

            # Pin quarto's R explicitly. quarto's rWrapper override is null,
            # so quarto would otherwise discover R from PATH; the env var
            # keeps that choice visible and stable.
            export QUARTO_R="$(which R)"
          '';
        in
        {
          devShells.default = pkgs.mkShell {
            name = "opi-base-shell";

            buildInputs = rPackages ++ systemDependencies;

            packages = rTools ++ devShellTools;

            env = shellEnv;

            passthru = {
              inherit shellEnv shellHook;
            };

            inherit shellHook;
          };
        };
    };
}
