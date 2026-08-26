# pi coding agent (https://github.com/badlogic/pi-mono), built from the
# published npm tarball. Not in nixpkgs, so this follows the same
# local-derivation pattern as lib/paper-bin.nix.
#
# Bumping `version` requires refreshing THREE things: the tarball hash, the
# npmDepsHash, and every entry in siblingIntegrity (the pi-mono packages are
# published in lockstep with the CLI). See the comment on siblingIntegrity.
{ pkgs
, version ? "0.84.3"
}:

let
  lib = pkgs.lib;

  tarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-0H3EF/eKFNrDdqh4tlVrUZYfEY95dx7jdTM9xRNWvHU=";
  };

  # Upstream generates npm-shrinkwrap.json with a custom script
  # (scripts/generate-coding-agent-shrinkwrap.mjs in pi-mono). That script
  # emits the six pi-mono sibling packages with a `resolved` registry URL but
  # no `integrity` field, which both prefetch-npm-deps and `npm ci` reject.
  # The tarballs are on the public registry; only the SRI hashes are missing.
  #
  # This must be patched in a *source* derivation rather than `postPatch`:
  # buildNpmPackage runs postPatch inside the npm-deps fetcher too, and that
  # derivation's stdenv has no node/jq on PATH.
  siblingIntegrity = {
    pi-agent-core = "sha512-VURr+xBRl3RxYcw3kT9Pn3yfi6LbRoCJgHF7h1mAblMjtLNV/MfG/RyF0uJizBAM886AEakSiw3j9c/aSngppg==";
    pi-ai         = "sha512-M0YUV8vNO3y2WwWSyY8ijKJV5W4gkSUixuvk+Z00ZBjsyMfsdXfITsHEwP1UIf09YRWXT6oGn0GlCamt+P32XQ==";
    pi-client     = "sha512-zfErYane+390W0xpBJ/FWCp6aktPpkpcIcXUeZiAziWLoxE80ZNQALRyOSa/gGS5V+1OkNnMYxRxbzN0zUvnOA==";
    pi-protocol   = "sha512-9a4g6WhLOvRqvsIOFaWxg/2gdrbY4Thclwj5ipLUPAWChfsDJ/8XdPc2sRhSOkD6EsxpEFJz3xppcfwI6EcZDg==";
    pi-telemetry  = "sha512-sgEkWoKrvSGaKn+YfLLFZmn+/A7B/w62eLwTD57nI+C9to8ITlFFVbgC2OtwvPnT3NFGHdCd53qhBEMIlptD1g==";
    pi-tui        = "sha512-fS6OEQKEEALnKa6Uw8LcgZZ+9CWck7f3MQSCETQp6leUgIFwMEDtKmOUnL9nsYm+RIPmy7OmplVxYRbV6hiaFg==";
  };

  jqFilter = lib.concatStringsSep " | " (lib.mapAttrsToList (name: hash:
    ''(.packages."node_modules/@earendil-works/${name}".integrity) //= "${hash}"''
  ) siblingIntegrity);

  src = pkgs.runCommand "pi-coding-agent-src-${version}"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      mkdir -p $out
      tar xzf ${tarball} -C $out --strip-components=1

      jq '${jqFilter}' $out/npm-shrinkwrap.json > $out/.shrinkwrap.patched
      mv $out/.shrinkwrap.patched $out/npm-shrinkwrap.json

      # package.json declares eight devDependencies that the generated
      # lockfile omits (its root entry has `devDependencies: []`). `npm ci`
      # validates the two against each other *before* honouring --omit=dev,
      # so the mismatch sends it to the registry and it dies on the sandbox's
      # only-if-cached policy. dist/ is prebuilt and dontNpmBuild is set, so
      # the dev toolchain is unused; drop it to make the pair consistent.
      jq 'del(.devDependencies)' $out/package.json > $out/.pkg.patched
      mv $out/.pkg.patched $out/package.json
    '';
in
pkgs.buildNpmPackage {
  pname = "pi-coding-agent";
  inherit version src;

  # engines.node is ">=22.19.0"; pin rather than inherit the default.
  nodejs = pkgs.nodejs_22;

  npmDepsHash = "sha256-QPAnjOkuJsiAh5imcGHJYurcNzJ5kM1z0jZFYiqQsoo=";

  # dist/ ships prebuilt in the published tarball (prepublishOnly runs the
  # TypeScript build), so there is nothing to compile here.
  dontNpmBuild = true;

  # The only optionalDependency is @mariozechner/clipboard, which is
  # darwin-only. pi-tui likewise ships native prebuilds for darwin and win32
  # only, so on Linux pi is pure JS plus one WASM blob.
  npmFlags = [ "--omit=optional" ];

  meta = {
    description = "pi coding agent CLI";
    homepage = "https://github.com/badlogic/pi-mono";
    mainProgram = "pi";
    # dist/ ships prebuilt in the npm tarball; nothing is compiled here.
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
