# The opi base shell: R + toolchain + dev tools. Exposed as devShells.<system>.base.
#
# Contract with modules/flake/opi.nix: the base shell exposes
# passthru.shellEnv and passthru.shellHook, which project shells layer on top
# of. Keep both when changing this file.
{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    let
      # CRAN-name -> pkgs.rPackages resolver (see lib/rPackages.nix).
      rp = import ../lib/rPackages.nix { inherit pkgs lib; };

      # Org packages (private, from their own flakes). Single source of truth is
      # lib/orgPackages.nix; overlays/default.nix puts them in pkgs.rPackages.
      org = import ../lib/orgPackages.nix { inherit inputs system lib; };

      # Org-standard R packages, present in every opi shell. Projects add their
      # own extras via opi.shells.<name>.rPackages.
      standardRPackages = [
        # tidyverse core
        "dplyr"
        "tidyr"
        "purrr"
        "stringr"
        "tibble"
        "readr"
        "lubridate"
        "forcats"
        "ggplot2"
        # ergonomics, pipelines, reporting
        "fs"
        "glue"
        "here"
        "targets"
        "qs2"
        "rmarkdown"
        "knitr"
        # data I/O + quality
        "readxl"
        "googledrive"
        "pointblank"
        # data platform
        "arrow"
      ]
      # org packages (wired via overlays/default.nix)
      ++ org.names;

      # Build/runtime tooling available to analysts. Nix builds R packages in
      # their own closures, so these are for interactive/ad-hoc work, not for
      # building project R packages.
      systemDependencies = with pkgs; [
        # Generic source-build tooling
        gcc
        gnumake
        cmake
        pkg-config

        # Rust toolchain (ojoutils has Rust extensions)
        cargo
        rustc

        # Common native libs
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

        # Arrow / Abseil / SQLite / UDUNITS / DuckDB (used by ojoutils, sf, terra)
        arrow-cpp
        abseil-cpp
        sqlite
        udunits
        duckdb

        R
      ];

      # R tooling from nixpkgs.
      rTools = with pkgs; [
        jarl
        arf
        air-formatter
      ];

      # Quarto 1.9.x emits pandoc 3.8's `syntax-highlighting` defaults field,
      # but nixpkgs' pandoc predates that rename (nixpkgs#461018), so renders
      # fail with `Unknown option "syntax-highlighting"` (nixpkgs#519484).
      # 3.8.3 is the pandoc quarto 1.9 bundles upstream. Drop once nixpkgs ships
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
          installPhase = ''
            mkdir -p $out/bin
            mv bin/pandoc $out/bin/pandoc
          '';
          meta.mainProgram = "pandoc";
        };

      # Quarto uses the shell's own R (discovered from PATH, pinned via QUARTO_R).
      # rWrapper is null so quarto does not bake a separate R + ELF wrapper shim
      # into the closure (Positron cannot parse that shim). knitr/rmarkdown come
      # from the project's rPackages instead. Typst PDF engine is bundled.
      quarto = pkgs.quarto.override {
        pandoc = pandocForQuarto;
        rWrapper = null;
      };

      devShellTools = with pkgs; [
        git
        gh
        google-cloud-sdk
        quarto
        # Positron is launched from the shell so R and the IDE share one
        # environment. On Linux its bundled `ark` dlopens libR in-process and
        # must share glibc with R, so it has to come from this nixpkgs; launch
        # with `positron .` (or `nix develop -c positron .`).
        positron-bin
      ];

      fonts = with pkgs; [ source-sans ];
      fontsConf = pkgs.makeFontsConf { fontDirectories = fonts; };

      # Env vars exported to every opi shell. Downstream shells (opi module)
      # forward this whole set, so adding a variable here propagates to all
      # projects automatically. `env` makes them real env vars in the base
      # shell; `passthru` lets project shells read the set at eval time.
      shellEnv = {
        R_HOME = "${pkgs.R}/lib/R";
        FONTCONFIG_FILE = fontsConf;

        # Strict immutability: point R's user library at a read-only empty
        # store path so ad-hoc install.packages() cannot persist. Packages come
        # from the shell's rPackages (via R's setup hook -> R_LIBS_SITE).
        R_LIBS_USER = "${pkgs.emptyDirectory}";

        # R also sources machine-wide user config: ~/.Renviron (which can reset
        # R_LIBS_*/R_PROFILE and so defeat the immutability above) and
        # ~/.R/Makevars (which injects CFLAGS/LDFLAGS/BLAS into every local
        # source compile, e.g. devtools::load_all() on a package with compiled
        # code). Both pin away so a shell behaves identically on every machine:
        # R env vars and build flags belong in `opi.shells.<name>.env` (project)
        # or here (org default), never in a developer's home directory.
        R_ENVIRON_USER = "/dev/null";
        R_MAKEVARS_USER = "/dev/null";
      };

      shellHook = ''
        echo "opi base shell ready."
        echo "R: $(which R)"
        echo "R_HOME: $R_HOME"
        echo "air: $(air --version)"
        echo "arf: $(arf --version)"
        echo "jarl: $(jarl --version)"
        echo "quarto: $(quarto --version)"

        # Pin quarto's R explicitly (quarto's rWrapper override is null, so it
        # would otherwise discover R from PATH).
        export QUARTO_R="$(which R)"
      '';
    in
    {
      devShells.base = pkgs.mkShell {
        name = "opi-base-shell";

        buildInputs = systemDependencies ++ (rp.resolveMany standardRPackages);

        packages = rTools ++ devShellTools;

        env = shellEnv;

        passthru = {
          inherit shellEnv shellHook;
        };

        inherit shellHook;
      };
    };
}
