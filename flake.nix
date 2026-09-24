{
  description = "qshell - a Quickshell desktop shell for Hyprland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.qcommon = {
    url = "github:porl/qcommon";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, qcommon }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The shared qcommon components are copied in first, then qshell's own
      # files, so both resolve by name through QML's implicit directory import.
      qmlTree =
        pkgs:
        pkgs.runCommand "qshell-qml" { } ''
          mkdir -p $out/share/qshell/qml
          cp -r ${qcommon.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/qcommon/qml/. $out/share/qshell/qml/
          cp -r ${./qml}/. $out/share/qshell/qml/
        '';

      # The bridge needs the QML path at runtime; bake it in so the package is
      # self-contained (no wrapper script). `QSHELL_QML` overrides it for
      # running from a working tree.
      qshell =
        pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "qshell";
          version = "0.1.0";
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
          QSHELL_QML = "${qmlTree pkgs}/share/qshell/qml";

          meta = {
            description = "A Quickshell desktop shell for Hyprland";
            license = nixpkgs.lib.licenses.gpl3Plus;
            mainProgram = "qshell";
            platforms = systems;
          };
        };

      package =
        pkgs:
        pkgs.symlinkJoin {
          name = "qshell-0.1.0";
          paths = [
            (qshell pkgs)
            (qmlTree pkgs)
          ];
        };
    in
    {
      packages = forAllSystems (pkgs: {
        default = package pkgs;
      });

      checks = forAllSystems (pkgs: {
        build = qshell pkgs;

        clippy = pkgs.rustPlatform.buildRustPackage {
          pname = "qshell-clippy";
          version = "0.1.0";
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = [ pkgs.clippy ];
          doCheck = false;
          buildPhase = "cargo clippy --all-targets -- -D warnings";
          installPhase = "touch $out";
        };

        fmt = pkgs.runCommand "qshell-fmt-check" {
          nativeBuildInputs = [
            pkgs.cargo
            pkgs.rustfmt
          ];
        } ''
          cp -r ${self} src
          chmod -R u+w src
          cd src
          export CARGO_HOME=$TMPDIR/cargo-home
          cargo fmt --check
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            pkgs.rust-analyzer
            pkgs.quickshell
          ];
        };
      });
    };
}
