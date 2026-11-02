## environment setup

**install nix**

```bash
# determinate nix installer (use on BOTH mac and ubuntu/wsl instead of apt-nix:
# ... gives an up to date nix with flakes already turned on,
# ... identical profile paths across OSes, and survives macOS updates)
curl --proto '=https' --tlsv1.2 -fsSL <https://install.determinate.systems/nix> | sh -s -- install
```

*after Nix installs successfully:
open a fresh shell so the installer's PATH entries load (`exit` + re-enter)*

**machine config** <br>
*note: on determinate nix `/etc/nix/nix.conf` is regenerated on every daemon restart (see its header: "do not modify! this file will be replaced!")... put this block in `/etc/nix/nix.custom.conf` instead, which is included intentionally by determinate nix devs via `!include`*

```bash
# works identically on both mac and ubuntu/wsl:
sudo tee -a /etc/nix/nix.custom.conf >/dev/null <<'EOF'
extra-substituters = <https://rstats-on-nix.cachix.org> <https://okpolicy.cachix.org>
extra-trusted-public-keys = rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0= okpolicy.cachix.org-1:pFLte8SVSaNyikujumclfUsVCbdC9AkPyamQrh022h0=
EOF

# restart to properly utilize cache from cachix upon first build
# if mac:
sudo launchctl kickstart -k system/systems.determinate.nix-daemon 2>/dev/null || sudo launchctl kickstart -k system/org.nixos.nix-daemon
# if ubuntu/wsl:
sudo systemctl restart nix-daemon
```

*basic summary of approach: <br>providing root daemon with okpolicy cache id and public key so all users trust them natively<br>...(no @admin/@sudo trusted-users tags or global accept-flake-config = true needed)*

**MAKE SURE TO RESTART DAEMON TO PROPERLY UTILIZE CACHE FROM CACHIX UPON FIRST BUILD**

**direnv + nix-direnv:**
(NOTE: see optional mac/wsl differences)

```bash
# if mac:
brew install direnv
# if ubuntu/wsl:
sudo apt install direnv
# (or skip brew/apt and install direnv via nix too:
# nix profile install nixpkgs#direnv nixpkgs#nix-direnv

# nix-direnv must be installed via nix package manager
nix profile install nixpkgs#nix-direnv
mkdir ~/.config/direnv
# no install wires direnv to nix-direnv, that setup = this one line
echo 'source ~/.local/state/nix/profiles/profile/share/nix-direnv/direnvrc' > ~/.config/direnv/direnvrc

# these lines install the hook: a trigger owned by the shell that runs direnv at every prompt
# ...(direnv is a separate program and cannot edit shell's env by itself... the hook is the bridge)
# if mac:
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
exec zsh
# if ubuntu/wsl:
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
exec bash # or start a new session... the hook is not active in this one
```

*^
a wrong hook fails silently: bash ignores `.zshrc`, zsh ignores `.bashrc` <br>
good: `direnv version` prints and `grep -n "direnv hook" ~/.zshrc ~/.bashrc 2>/dev/null` shows one line in active shell's rc file*

---

## project setup

**1. step for feat/all-in: <br>
`flake.nix` cleanup:** need to remove the `nixConfig` block below from `flake.nix`<br>
(we're moving cache validation to `/etc/nix/nix.custom.conf` instead)

```nix
# nixConfig = {
#   extra-substituters = [ "<https://rstats-on-nix.cachix.org>" ];
#   extra-trusted-public-keys = [
#     "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
#   ];
# };
```

**2. enable direnv in the project folder**

```bash
printf 'use flake\n' > .envrc # this project's env = this flake's devshell
direnv allow # per project, per .envrc
```

if caches aren't being used (building from source instead of copying from cachix)... three causes, in order:

1. `extra-substituters` and `extra-trusted-public-keys` are not in `/etc/nix/nix.custom.conf`
2. the daemon wasn't restarted after the block landed
3. inline `#` comments were left on the same line as the settings in `/etc/nix/nix.custom.conf`

all three mean the okpolicy libraries are building from source instead of coming from cache

**3. error in feat/all-in: the shipped stale `flake.lock`:**

```
error: opi.rPackages: unknown package(s): ojodb, ojothemes, ojoutils, ojoregex.
```

reads as a package-set problem... a committed stale `flake.lock` is the actual cause <br>
remove it and let it regenerate on build

```bash
rm flake.lock # direnv will automatically eval and regenerate the lock against current config
direnv allow
```

**mac quirk: the jarl wall** <br>
*known issue (mac darwin only): nix build hard fails at jarl's test phase (`test result: FAILED. 312 passed; 33 failed`) <br>
current fix: add the block below to `overlays/system.nix`<br>
what it does: disable jarl's test suite for now*<br>

```nix
final: prev: {
    jarl = prev.jarl.overrideAttrs (old: {
                doCheck = false;
});}
```

---

## what good looks like

**should see direnv banner on entry into enabled project**

```bash
command -v R # should be /nix/store/...
direnv status | grep "Found RC allowed" # should be "allowed true" or "allowed 0"
nix config show | grep substituters # should show <https://rstats-on-nix.cachix.org> (and okpolicy.cachix.org)
nix config show | grep trusted-public-keys # should show rstats-on-nix.cachix.org-1:... (and okpolicy.cachix.org-1:...)
```

```r
Rscript -e '.libPaths()' # shows Nix store paths
Rscript -e 'arrow::arrow_with_gcs()' # TRUE
```