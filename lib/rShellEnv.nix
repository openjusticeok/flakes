# The environment every opi artifact inherits.
#
# One function, read by the dev shell (`lib/mkOpiShell.nix`) and the runtime
# closure (`lib/mkRenv.nix`). That is invariant 10 in code: a dev shell and an
# image cannot disagree about fonts, R_HOME or the immutability pins, because
# they are not separate values — an image that forgot `FONTCONFIG_FILE` would
# render plots in DejaVu instead of Source Sans 3, silently (ARCHITECTURE §2b).
{pkgs}: {
  R_HOME = "${pkgs.R}/lib/R";

  # ragg/fontconfig resolve glyphs through this file; the font closure it
  # references is what keeps plot output identical in a shell and in an image.
  FONTCONFIG_FILE = pkgs.makeFontsConf {fontDirectories = [pkgs.source-sans];};

  # Strict immutability: R's user library is a read-only empty store path, so
  # ad-hoc install.packages() cannot persist. Packages come from the artifact's
  # rPackages (in a shell via R's setup hook -> R_LIBS_SITE; in the runtime
  # closure via R_LIBS_SITE computed directly).
  R_LIBS_USER = "${pkgs.emptyDirectory}";

  # R also sources machine-wide user config: ~/.Renviron (which can reset
  # R_LIBS_*/R_PROFILE and so defeat the immutability above) and ~/.R/Makevars
  # (which injects CFLAGS/LDFLAGS/BLAS into every local source compile, e.g.
  # devtools::load_all() on a package with compiled code). Both pin away so an
  # artifact behaves identically on every machine.
  R_ENVIRON_USER = "/dev/null";
  R_MAKEVARS_USER = "/dev/null";
}
