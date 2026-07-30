# Derivazione usabile anche senza flake: pkgs.callPackage ./packaging/nix/package.nix { }
#
# version va tenuta allineata a VERSION in lib/00_header.sh. La verifica non è
# a occhio: tests/test_packaging.sh fallisce se le due divergono.
{ lib
, stdenv
, makeWrapper
, bash
, imagemagick
, librsvg
, libnotify
, wl-clipboard
, wtype
, xclip
, xdotool
}:

stdenv.mkDerivation {
  pname = "cli-image-paste";
  version = "2.0.0";

  src = lib.cleanSource ../..;

  nativeBuildInputs = [ makeWrapper ];

  makeFlags = [ "PREFIX=${placeholder "out"}" ];

  # Su Nix i tool di runtime non stanno nel PATH dell'utente per costruzione,
  # e il degrado silenzioso del tool li renderebbe semplicemente assenti per
  # sempre senza che nessuno capisca perché. Il wrapper li mette in coda al
  # PATH: quelli dell'utente, se ci sono, continuano a vincere.
  postInstall = ''
    wrapProgram $out/bin/paste-image \
      --suffix PATH : ${lib.makeBinPath [
        bash
        imagemagick
        librsvg
        libnotify
        wl-clipboard
        wtype
        xclip
        xdotool
      ]}
  '';

  # La suite gira contro l'ambiente: sessione grafica, binari finti su PATH,
  # ShellCheck. Nella sandbox verificherebbe qualcosa di diverso da quello che
  # verifica in CI, e un check che misura altro è peggio di nessun check.
  doCheck = false;

  meta = with lib; {
    description = "Paste clipboard images into the active terminal as a file path";
    homepage = "https://github.com/AndreaBonn/cli-image-paste";
    license = licenses.mit;
    mainProgram = "paste-image";
    # X11 e Wayland: non c'è niente da portare altrove.
    platforms = platforms.linux;
  };
}
