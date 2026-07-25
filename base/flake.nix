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
        in
        {
          devShells.default = pkgs.mkShell {
            name = "opi-base-shell";

            buildInputs = rPackages ++ systemDependencies ++ rTools ++ devShellTools ++ [ rWrapper ];

            packages = [ rWrapper ] ++ rTools ++ devShellTools;

            R_HOME = "${pkgs.R}/lib/R";

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
              export R_LIBS_USER="$PWD/rv/library"
              mkdir -p "$R_LIBS_USER"
            '';
          };
        };
    };
}
