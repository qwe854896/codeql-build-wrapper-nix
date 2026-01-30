# Package derivation for hello-c
# Can be used standalone: nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
{
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "hello-c";
  version = "0.1.0";

  src = ./.;

  installPhase = ''
    make install DESTDIR="" PREFIX="$out"
  '';

  meta = with lib; {
    description = "Simple Hello World C program for CodeQL testing";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
