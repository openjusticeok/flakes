# The org's private R packages.
#
# Each is a self-contained flake consumed as an input in flake.nix (declared
# there with `inputs.nixpkgs.follows = "nixpkgs"`). This file is the single
# source of truth for *which* ones exist, so the private-package overlay, the
# base shell's standard set, and the per-package dev shells cannot drift apart.
#
# Adding a package: add the input in flake.nix, add its name here, then run
# `nix flake update <name>`.
{ inputs, system, lib }:
let
  names = [
    "ojodb"
    "ojoregex"
    "ojothemes"
    "ojoutils"
  ];

  # An input declared here but absent from the lock is the signature of a stale
  # lock in the consuming flake (the opi lock is what carries these inputs).
  # Fail with the fix rather than silently shipping a base shell without the
  # org packages. Reading either attribute triggers this.
  missing = builtins.filter (name: !(inputs ? ${name})) names;

  packages = lib.genAttrs names (name: inputs.${name}.packages.${system}.${name});
in
if missing != [ ] then
  throw ''
    opi: no flake input(s) for org package(s): ${lib.concatStringsSep ", " missing}.
    The consuming flake's lock is stale; re-lock the opi input:
      nix flake lock --update-input opi
    (or `nix flake update`).
  ''
else
  { inherit names packages; }
