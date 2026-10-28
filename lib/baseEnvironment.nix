# What every opi shell contains before the caller adds anything.
#
# This is org policy — the standard R set, the toolchain and native libraries,
# the interactive tools, the quarto pin — kept apart from the mechanism that
# composes a shell (lib/mkOpiShell.nix). Pin changes land here; composition
# changes land there. There is no second copy of any of it: the base shell,
# project shells, and per-package dev shells all read this file, so they cannot
# drift apart.
{pkgs}: let
  # The org's private R packages, by name. Input-free on purpose: the packages
  # themselves reach pkgs.rPackages through overlays/default.nix, so naming them
  # does not require the org's flake inputs (a consuming project does not have
  # them as inputs of its own).
  # The org's R package names (standard set + private packages), by CRAN name.
  # Input-free on purpose: the derivations reach pkgs.rPackages through
  # overlays/default.nix, so naming them does not require the org's flake inputs
  # (a consuming project does not have them as inputs of its own).
  names = import ./packageNames.nix;

  # Quarto 1.9.x emits pandoc 3.8's `syntax-highlighting` defaults field,
  # but nixpkgs' pandoc predates that rename (nixpkgs#461018), so renders
  # fail with `Unknown option "syntax-highlighting"` (nixpkgs#519484).
  # 3.8.3 is the pandoc quarto 1.9 bundles upstream. Drop once nixpkgs ships
  # pandoc >= 3.8.
  pandocForQuarto = let
    inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
    systemTag =
      if isDarwin
      then
        (
          if isAarch64
          then "arm64-macOS"
          else "x86_64-macOS"
        )
      else if isAarch64
      then "linux-arm64"
      else "linux-amd64";
    extension =
      if isDarwin
      then "zip"
      else "tar.gz";
    hash =
      if isDarwin
      then
        (
          if isAarch64
          then "sha256-Pq6zvRCYKuy6XddhWHRaT4Ba+zmrcqUZu6JTPJjOAC0="
          else "sha256-ki41wCENfKIO6TJ4ETYdbX8O8K3aCJ4OdMs3VsPXE/k="
        )
      else
        (
          if isAarch64
          then "sha256-FmpaNzh+sQvUxPJCqBCb7vdVrB6NTrA5xrXr0dkY2Nc="
          else "sha256-wiT6uJ+CfTYjOA7LfBB4wWPHachJoUrCfo07+7kUybQ="
        );
  in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "pandoc";
      version = "3.8.3";
      src = pkgs.fetchurl {
        url = "https://github.com/jgm/pandoc/releases/download/3.8.3/pandoc-3.8.3-${systemTag}.${extension}";
        inherit hash;
      };
      nativeBuildInputs = [pkgs.unzip];
      installPhase = ''
        mkdir -p $out/bin
        mv bin/pandoc $out/bin/pandoc
      '';
      meta.mainProgram = "pandoc";
    };

  # Quarto uses the shell's own R (discovered from PATH, pinned via QUARTO_R).
  # rWrapper is null so quarto does not bake a separate R + ELF wrapper shim
  # into the closure (Positron cannot parse that shim). knitr/rmarkdown come
  # from the shell's rPackages instead. Typst PDF engine is bundled.
  quarto = pkgs.quarto.override {
    pandoc = pandocForQuarto;
    rWrapper = null;
  };
in {
  # CRAN names: mkOpiShell resolves them against pkgs.rPackages and puts them on
  # R_LIBS_SITE via R's setup hook. Org packages are wired into pkgs.rPackages
  # by overlays/default.nix, so they are just more names here.
  rPackages = names.standard ++ names.org;

  # Build/runtime tooling available to analysts. Nix builds R packages in their
  # own closures, so these are for interactive/ad-hoc work, not for building
  # project R packages. (S3 measures whether the heavy ones still earn a place
  # in every shell.)
  buildInputs = with pkgs; [
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

  # Tools on PATH: R formatting/linting, and the interactive environment.
  packages = with pkgs; [
    jarl
    arf
    air-formatter

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
}
