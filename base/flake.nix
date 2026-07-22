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
          rv = pkgs.rustPlatform.buildRustPackage {
            pname = "rv";
            version = "0.22.2";

            src = pkgs.fetchFromGitHub {
              owner = "A2-ai";
              repo = "rv";
              rev = "v0.22.2";
              hash = "sha256-v9VJ54EZ/UcbELn5nHoyppOrHWhWOagJqoBpVWkAeTg=";
            };

            cargoHash = "sha256-rphrVNnhEKMDUABuAtcUErNduu6zuyY7uDLgpMFCMcU=";

            buildFeatures = [ "cli" ];

            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];

            doCheck = false;
          };

          arf = pkgs.rustPlatform.buildRustPackage {
            pname = "arf";
            version = "0.4.3";
            src = pkgs.fetchFromGitHub {
              owner = "eitsupi";
              repo = "arf";
              rev = "v0.4.3";
              hash = "sha256-CceBGYa24VsJBG7Aza8EcDJe0DoI4+mCXQiZ+HLF4A4=";
            };
            cargoHash = "sha256-DHMEmBYrONfxEIOmc9lTN9cEukfJrRg62Lzj3aPnQak=";
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];
            doCheck = false;
          };

          jarl = pkgs.rustPlatform.buildRustPackage {
            pname = "jarl";
            version = "0.5.0";
            src = pkgs.fetchFromGitHub {
              owner = "etiennebacher";
              repo = "jarl";
              rev = "0.5.0";
              hash = "sha256-MFP1xMNnJ9mfHuUu6hqE9B7nRgI2HfXBpblo3sFnAwo=";
            };
            cargoHash = "sha256-Rhv9Wku/bRl28nrXYof+6VAgl2K4ysILRQa1v19r0pU=";
            doCheck = false;
          };

          air = pkgs.rustPlatform.buildRustPackage {
            pname = "air";
            version = "0.10.0";
            src = pkgs.fetchFromGitHub {
              owner = "posit-dev";
              repo = "air";
              rev = "0.10.0";
              hash = "sha256-u0icSo6aW6tLgY57RPAoVte5Awn16FLIvZEeeYNr5fk=";
            };
            cargoHash = "sha256-51xkTVs6j7n0os5wHWxpFC/uLHm3tz+SiWUHsd+bNRw=";
            doCheck = false;
          };

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

            # Arrow C++ libs (ojoutils depends on arrow)
            arrow-cpp

            R
          ];

          devShellTools = [
            rv
            arf
            jarl
            air
          ];

          rWrapper = pkgs.rWrapper.override {
            packages = rPackages;
          };
        in
        {
          devShells.default = pkgs.mkShell {
            name = "opi-base-shell";

            buildInputs = rPackages ++ systemDependencies ++ devShellTools ++ [ rWrapper ];

            packages = [ rWrapper rv arf jarl air ];

            R_HOME = "${pkgs.R}/lib/R";

            shellHook = ''
              echo "opi base shell ready."
              echo "R: $(which R)"
              echo "R_HOME: $R_HOME"
              echo "rv: $(rv --version)"
              echo "air: $(air --version)"
              echo "arf: $(arf --version)"
              echo "jarl: $(jarl --version)"

              # Expose native library directories at runtime so rv-installed R
              # packages that link against Nix-provided libs (openssl, curl,
              # arrow-cpp, etc.) can find them after installation.
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath systemDependencies}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

              # V8's configure script downloads a static libv8 build when this
              # variable is set, avoiding a dependency on a system libv8 package.
              export DOWNLOAD_STATIC_LIBV8=1

              # Let rv manage project-local R packages without touching the Nix R library
              export R_LIBS_USER="$PWD/rv/library"
              mkdir -p "$R_LIBS_USER"
            '';
          };
        };
    };
}
