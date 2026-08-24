{
  description = "Pinned development and ASIC implementation environment for Codex RV64";

  nixConfig = {
    extra-substituters = [ "https://openlane.cachix.org" ];
    extra-trusted-public-keys = [
      "openlane.cachix.org-1:qqdwh+QMNGmZAuyeQJTH9ErW57OWSvdtuwfBKdS254E="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/805a384895c696f802a9bf5bf4720f37385df547";
    openlane.url = "github:efabless/openlane2/b89f7866fd3d19da470220baf89d0e7804962941";
  };

  outputs = { self, nixpkgs, openlane }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      edaPkgs = openlane.legacyPackages.${system};
      sv2vPackage = pkgs.stdenv.mkDerivation {
        pname = "sv2v";
        version = "0.0.13";
        src = pkgs.fetchurl {
          url = "https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Linux.zip";
          hash = "sha256-VSeZodds0Xe5tMxjo+d4I6PSputOwAZWkoir7/KOH/g=";
        };
        nativeBuildInputs = with pkgs; [ autoPatchelfHook unzip ];
        buildInputs = with pkgs; [ gmp ];
        strictDeps = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 sv2v "$out/bin/sv2v"
          install -Dm644 CHANGELOG.md LICENSE NOTICE README.md -t "$out/share/doc/sv2v"
          runHook postInstall
        '';
        meta = with pkgs.lib; {
          description = "SystemVerilog to Verilog conversion tool";
          homepage = "https://github.com/zachjs/sv2v";
          license = licenses.bsd3;
          platforms = [ "x86_64-linux" ];
        };
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          bash
          boolector
          cachix
          clang
          gcc
          git
          gnumake
          python3
          python3Packages.pyyaml
          sv2vPackage
          edaPkgs.verilator
          edaPkgs.yosys
          edaPkgs.yosys-sby
          z3
        ];
        SOURCE_DATE_EPOCH = "1787529600";
        TZ = "UTC";
        LC_ALL = "C.UTF-8";
      };

      packages.${system}.openlane = openlane.packages.${system}.default;

      checks.${system}.smoke = pkgs.runCommand "codex-rv64-smoke" {
        nativeBuildInputs = with pkgs; [
          bash clang gcc gnumake python3 python3Packages.pyyaml sv2vPackage
          edaPkgs.verilator edaPkgs.yosys
        ];
        src = self;
      } ''
        cp -R "$src" source
        chmod -R u+w source
        cd source
        patchShebangs scripts
        make smoke BUILD_DIR="$TMPDIR/build"
        touch "$out"
      '';
    };
}
