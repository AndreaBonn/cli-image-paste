{
  description = "Paste clipboard images into the active terminal as a file path";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Nessun flake-utils: servirebbe una sola funzione, e un input in più è un
  # input in più da aggiornare per un progetto che sta in quindici file bash.
  outputs = { self, nixpkgs }:
    let
      # X11 e Wayland: non c'è nulla da costruire altrove.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        cli-image-paste = pkgs.callPackage ./packaging/nix/package.nix { };
        default = cli-image-paste;
      });

      # Lo shell di sviluppo porta ciò che serve al runner: ShellCheck per il
      # gate statico, ImageMagick per le trasformazioni, i due backend di
      # appunti perché la suite esercita entrambe le sessioni.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            shellcheck
            imagemagick
            wl-clipboard
            wtype
            xclip
            xdotool
            libnotify
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
