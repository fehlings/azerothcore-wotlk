{
  description = "Complete Open Source and Modular solution for MMO";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    process-compose-flake.url = "github:xtian/process-compose-flake/patch-1";
    services-flake.url    = "github:juspay/services-flake";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.process-compose-flake.flakeModule
      ];
      systems =
        [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          src = ./.;

          clientData = pkgs.fetchzip {
            url       = "https://github.com/wowgaming/client-data/releases/download/v19/Data.zip";
            hash      = "sha256-My6ZUYj5dze2rIyqJeOVUbHDUeZSsruiJsRWUDG391g=";
            stripRoot = false;
          };

          azerothcore = pkgs.clangStdenv.mkDerivation {
            pname   = "azerothcore";
            version = "unstable";
            inherit src;

            nativeBuildInputs = with pkgs; [ cmake git ];
            buildInputs = with pkgs; [ boost bzip2 mysql84 openssl readline zlib];

            cmakeFlags = [
              "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}/env/dist/"
              "-DWITH_WARNINGS=1"
              "-DTOOLS_BUILD=all"
              "-DSCRIPTS=static"
              "-DMODULES=static"
            ];

            postInstall = ''
              for f in $out/env/dist/etc/*.conf.dist; do
                install -m444 "$f" "''${f%.dist}"
              done
            '';
          };
        in
        {
          packages.default = azerothcore;

          devShells.default = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
            nativeBuildInputs = with pkgs; [
              cmake
            ];
            buildInputs = with pkgs; [
              boost
              openssl
              mysql84
              readline
              bzip2
              zlib
            ];
            AC_DATA_DIR = "${clientData}";
          };

          process-compose."dev" = {
            imports = [
              inputs.services-flake.processComposeModules.default
            ];

            services.mysql."acore-db" = {
              enable    = true;
              package   = pkgs.mysql84;
              dataDir   = "./.mysql";

              initialDatabases = [
                { name = "acore_world"; }
                { name = "acore_characters"; }
                { name = "acore_auth"; }
              ];

              ensureUsers = [
                  {
                    name     = "acore";
                    ensurePermissions = {
                      "acore_world.*"      = "ALL PRIVILEGES";
                      "acore_characters.*" = "ALL PRIVILEGES";
                      "acore_auth.*"       = "ALL PRIVILEGES";
                    };
                  }
              ];
            };

            settings.processes.authserver = {
              command = "${azerothcore}/env/dist/bin/authserver";
              is_tty = true;
              environment = {
                AC_DATA_DIR = "${clientData}";
                AC_LOGIN_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_auth";
                AC_WORLD_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_world";
                AC_CHARACTER_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_characters";
                AC_SOURCE_DIRECTORY = "${src}";
              };
              depends_on."acore-db".condition = "process_healthy";
            };

            settings.processes.worldserver = {
              command = "${azerothcore}/env/dist/bin/worldserver";
              is_interactive = true;
              environment = {
                AC_DATA_DIR = "${clientData}";
                AC_LOGIN_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_auth";
                AC_WORLD_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_world";
                AC_CHARACTER_DATABASE_INFO = "127.0.0.1;3306;acore;;acore_characters";
                AC_SOURCE_DIRECTORY = "${src}";
              };
              depends_on."acore-db".condition   = "process_healthy";
              depends_on."authserver".condition = "process_started";
            };
          };
        };
    };
}
