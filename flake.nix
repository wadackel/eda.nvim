{
  description = "eda.nvim development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          selene-luajit = pkgs.selene.overrideAttrs (old: {
            cargoBuildFeatures = (old.cargoBuildFeatures or []) ++ [ "luajit" ];
          });
          lintPackages = [
            pkgs.stylua
            selene-luajit
          ];
          typecheckPackages = [
            pkgs.just
            pkgs.jq
            pkgs.neovim
            pkgs.lua-language-server
          ];
        in
        {
          default = pkgs.mkShell {
            packages = lintPackages ++ typecheckPackages ++ [
              pkgs.git
              pkgs.panvimdoc
              pkgs.vhs
            ];
          };

          ci = pkgs.mkShell {
            packages = lintPackages ++ [
              pkgs.just
              pkgs.panvimdoc
            ];
          };

          typecheck = pkgs.mkShell {
            packages = typecheckPackages;
          };
        }
      );
    };
}
