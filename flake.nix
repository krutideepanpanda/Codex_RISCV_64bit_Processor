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
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          bash
          boolector
          cachix
          gcc
          git
          gnumake
          python3
          python3Packages.pyyaml
          sv2v
          symbiyosys
          verilator
          yosys
          z3
        ];
        SOURCE_DATE_EPOCH = "1787529600";
        TZ = "UTC";
        LC_ALL = "C.UTF-8";
      };

      packages.${system}.openlane = openlane.packages.${system}.default;

      checks.${system}.smoke = pkgs.runCommand "codex-rv64-smoke" {
        nativeBuildInputs = with pkgs; [
          bash gcc gnumake python3 python3Packages.pyyaml sv2v verilator yosys
        ];
        src = self;
      } ''
        cp -R "$src" source
        chmod -R u+w source
        cd source
        make smoke BUILD_DIR="$TMPDIR/build"
        touch "$out"
      '';
    };
}
