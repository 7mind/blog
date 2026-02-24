{
  description = "7mind blog development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            ruby_3_3
            bundler
            gcc
            gnumake
            pkg-config
            libffi
            libxml2
            libxslt
            zlib
            git
          ];

          shellHook = ''
            export BUNDLE_PATH="$PWD/vendor/bundle"
            export BUNDLE_JOBS="4"
            export BUNDLE_RETRY="3"
          '';
        };
      });
}
