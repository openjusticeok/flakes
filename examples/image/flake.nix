{
  description = "opi image example: a Shiny app deployed as an OCI image";

  inputs = {
    opi.url = "path:../..";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs @ {
    opi,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      inherit (opi.lib) systems;

      imports = [opi.flakeModules.default];

      # This is the whole pilot shape (ARCHITECTURE §4, §9 step 3):
      #
      #   nix build .#dashboard-image          the OCI image
      #   nix run   .#dashboard-push -- --dry-run
      #   nix run   .#dashboard-push           push, resolve digest, pin tfvars
      #
      # One declaration produces the dev shell, the runtime closure CI runs, and
      # the image — so the app cannot be tested against a different R than it
      # ships with.
      perSystem = {...}: {
        opi.shells.default = {
          # The `shiny` bundle is the *tooling* (chromium + node for shinytest2),
          # not the R package — an app whose deps are missing builds a perfectly
          # valid image that fails at boot. Name the app's own packages here.
          bundles = ["shiny"];
          rPackages = ["shiny" "bslib"];
        };

        opi.images.dashboard = {
          # Contents and env come from that shell's runtime closure: same R, same
          # R packages, same env (invariant 10). No second package list.
          shell = "default";

          repository = "us-central1-docker.pkg.dev/EXAMPLE_PROJECT/EXAMPLE_REPO";

          # Assets land at the image root (a store path's contents are unpacked at
          # `/`), and the runtime wrapper's `bin` lands at `/bin` — so
          # `/bin/Rscript` is this container's R, with R_LIBS_SITE and fonts baked
          # in. Naming it directly means the image needs no shell.
          contents = [./app.R];
          workingDir = "/";

          entrypoint = [
            "/bin/Rscript"
            "-e"
            "shiny::runApp('/app.R', host = '0.0.0.0', port = as.integer(Sys.getenv('PORT', '8080')), launch.browser = FALSE)"
          ];

          # inv 13, runtime half: the entrypoint exits 78 (EX_CONFIG) at boot if
          # these are unset, instead of failing on first use. The names are also
          # an image label, so the project's tofu can compare them with what it
          # actually mounts from Secret Manager.
          requiredEnv = [];
          port = 8080;

          # Left at its default: the repo root's infra/tofu/terraform.tfvars.
          # Set `migrateJob` if the app has a job that must run after apply.
          gcpProject = "EXAMPLE_PROJECT";
          region = "us-central1";
        };
      };
    };
}
