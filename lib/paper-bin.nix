{ pkgs
, version ? "v0.16.0"
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  platform = {
    aarch64-linux = "arm64";
    x86_64-linux = "amd64";
  }.${system} or (throw "paper-bin is not available for ${system}");

  hashes = {
    arm64 = "sha256-hd0ONLjw97BEgafcA3Uw7KxuC6pvu9jMseNDlrc4L+o=";
    amd64 = "sha256-ZtRnD7Ifn2VvfQGT1/hnboOn6DSLCorw4pMpRi8Gew0=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "paper-bin";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://download.papercompute.com/${version}/linux/${platform}/paper";
    hash = hashes.${platform};
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/paper"
    ln -s paper "$out/bin/paperd"

    runHook postInstall
  '';

  meta = {
    description = "Paper CLI binary from the public Paper Compute release bucket";
    homepage = "https://papercompute.com";
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
