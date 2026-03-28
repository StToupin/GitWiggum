{
    inputs = {
        ihp.url = "github:vcombey/ihp?ref=b3ec7b8c0b2dfdb486b67142583cd0c04944769b";
        nixpkgs.follows = "ihp/nixpkgs";
        flake-parts.follows = "ihp/flake-parts";
        devenv.follows = "ihp/devenv";
        systems.follows = "ihp/systems";
        devenv-root = {
            url = "file+file:///dev/null";
            flake = false;
        };
    };

    outputs = inputs@{ self, nixpkgs, ihp, flake-parts, systems, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {

            systems = import systems;
            imports = [ ihp.flakeModules.default ];

            perSystem = { pkgs, lib, self', config, ... }:
                let
                    ngrokUrlScript = ''
                        set -euo pipefail

                        api_url="''${NGROK_API_URL:-http://127.0.0.1:4040}"
                        timeout_seconds="''${NGROK_API_TIMEOUT_SECONDS:-30}"
                        poll_seconds="''${NGROK_API_POLL_SECONDS:-1}"
                        api_endpoint="''${api_url%/}/api/tunnels"
                        deadline=$((SECONDS + timeout_seconds))

                        while (( SECONDS < deadline )); do
                            response="$(curl --silent --show-error --fail "$api_endpoint" 2>/dev/null || true)"

                            if [ -n "$response" ]; then
                                public_url="$(
                                    printf '%s' "$response" | node -e 'const fs = require("fs"); const payload = fs.readFileSync(0, "utf8"); try { const data = JSON.parse(payload); const tunnels = Array.isArray(data.tunnels) ? data.tunnels : []; const preferredTunnel = tunnels.find((tunnel) => typeof tunnel.public_url === "string" && tunnel.public_url.startsWith("https://")) ?? tunnels.find((tunnel) => typeof tunnel.public_url === "string" && tunnel.public_url.startsWith("http://")); if (preferredTunnel) { process.stdout.write(preferredTunnel.public_url.replace(/\/$/, "")); } } catch (_) {}'
                                )"

                                if [ -n "$public_url" ]; then
                                    printf '%s\n' "$public_url"
                                    exit 0
                                fi
                            fi

                            sleep "$poll_seconds"
                        done

                        echo "Timed out waiting for an ngrok tunnel at $api_endpoint" >&2
                        exit 1
                    '';
                    syncSharedSecretsScript = ''
                        if [ -x ./scripts/install-secrets.sh ] && [ -f ./secrets/shared.env ]; then
                            if ! ./scripts/install-secrets.sh --quiet; then
                                echo "Warning: automatic shared secret sync failed. Continuing with the current .env.secrets if present." >&2
                            fi
                        fi

                        if [ -f ./.env.secrets ]; then
                            set -o allexport
                            source ./.env.secrets
                            set +o allexport
                        fi
                    '';
                    dockerImageEtcCommands = ''
                        mkdir -p etc root tmp var/empty
                        chmod 1777 tmp
                        chmod 0755 etc root var var/empty

                        cat > etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/sh
sshd:x:74:74:sshd privilege separation user:/var/empty:/bin/sh
git:x:1000:1000:git ssh user:/var/empty:/bin/sh
nobody:x:65534:65534:nobody:/var/empty:/sbin/nologin
EOF

                        cat > etc/group <<'EOF'
root:x:0:
sshd:x:74:
git:x:1000:
nogroup:x:65534:
EOF

                        cat > etc/nsswitch.conf <<'EOF'
hosts: files dns
networks: files
passwd: files
group: files
shadow: files
EOF
                    '';
                    fastBuildHaskellPackage = pkg:
                        pkgs.haskell.lib.disableLibraryProfiling (
                            pkgs.haskell.lib.dontCheck (
                                pkgs.haskell.lib.dontHaddock pkg
                            )
                        );
                    appHaskellPackages = p:
                        let
                            aeson-decode-loose = fastBuildHaskellPackage (p.callCabal2nix "aeson-decode-loose" ./Packages/aeson-decode-loose { });
                            ihp = fastBuildHaskellPackage p.ihp;
                            ihp-auth-support = fastBuildHaskellPackage (p.callCabal2nix "ihp-auth-support" ./Plugins/ihp-auth-support { });
                            ihp-job-dashboard = fastBuildHaskellPackage p.ihp-job-dashboard;
                            ihp-log = fastBuildHaskellPackage p.ihp-log;
                            ihp-mail = fastBuildHaskellPackage p.ihp-mail;
                            ihp-openai = fastBuildHaskellPackage p.ihp-openai;
                            ihp-oauth-github = fastBuildHaskellPackage (p.callCabal2nix "ihp-oauth-github" ./Plugins/ihp-oauth-github { });
                            ihp-oauth-google = fastBuildHaskellPackage (p.callCabal2nix "ihp-oauth-google" ./Plugins/ihp-oauth-google { });
                            ihp-sentry = fastBuildHaskellPackage (p.callCabal2nix "ihp-sentry" ./Plugins/ihp-sentry { });
                            ihp-stripe = fastBuildHaskellPackage (p.callCabal2nix "ihp-stripe" ./Plugins/ihp-stripe { });
                            ihp-typed-sql = fastBuildHaskellPackage p.ihp-typed-sql;
                        in
                        with p; [
                            aeson-decode-loose
                            ihp
                            cabal-install
                            base
                            cryptonite
                            blaze-html
                            cmark
                            hspec
                            lens
                            network
                            openapi3
                            skylighting
                            skylighting-core
                            skylighting-format-blaze-html
                            wai
                            text
                            toml-parser
                            aeson-pretty
                            zlib
                            ihp-auth-support
                            ihp-job-dashboard
                            ihp-log
                            ihp-mail
                            ihp-openai
                            ihp-oauth-github
                            ihp-oauth-google
                            ihp-sentry
                            ihp-stripe
                            ihp-typed-sql
                            wreq
                        ];
                    ihpFilter = inputs.ihp.inputs."nix-filter".lib;
                    ihpProdServer = { optimized, optimizationLevel }:
                        import ./Config/nix/ihp-prod-server-with-compile-db.nix {
                            inherit ihp optimized optimizationLevel pkgs;
                            ghc = pkgs.ghc;
                            haskellDeps = config.ihp.haskellPackages;
                            otherDeps = _: [];
                            projectPath = config.ihp.projectPath;
                            rtsFlags = config.ihp.rtsFlags;
                            relationSupport = config.ihp.relationSupport;
                            appName = config.ihp.appName;
                            filter = ihpFilter;
                            ihp-env-var-backwards-compat = ihp.packages.${pkgs.system}.ihp-env-var-backwards-compat;
                            ihp-static = ihp.packages.${pkgs.system}.ihp-static;
                            static = self'.packages.static;
                        };
                in {
                ihp = {
                    appName = "gitWiggum";
                    enable = true;
                    projectPath =
                        builtins.path {
                            path = ./.;
                            name = "gitWiggum-project";
                            filter =
                                path: _type:
                                let
                                    root = toString ./.;
                                    pathString = toString path;
                                    relativePath =
                                        if pathString == root
                                            then "."
                                            else lib.removePrefix "${root}/" pathString;
                                    ignoredPaths =
                                        [ "Plugins"
                                          ".git"
                                          ".github"
                                          ".githooks"
                                          ".vscode"
                                          "IaC"
                                          "cli"
                                          "data"
                                          "doc"
                                          "dist-newstyle"
                                          "migrate"
                                          "rgh"
                                          "result"
                                          "scripts"
                                          ".devenv"
                                          ".direnv"
                                        ];
                                    isIgnoredPath = ignoredPath:
                                        relativePath == ignoredPath
                                            || lib.hasPrefix "${ignoredPath}/" relativePath;
                                in
                                    !(lib.any isIgnoredPath ignoredPaths);
                        };
                    packages = with pkgs; [
                        awscli2
                        cacert
                        codex
                        git
                        haskellPackages.fourmolu
                        haskellPackages.ihp-hsx
                        just
                        nodejs
                    ];
                    haskellPackages = appHaskellPackages;
                };

                packages = {
                    optimized-prod-server = lib.mkForce (ihpProdServer {
                        optimized = true;
                        optimizationLevel = config.ihp.optimizationLevel;
                    });
                    unoptimized-prod-server = lib.mkForce (ihpProdServer {
                        optimized = false;
                        optimizationLevel = "0";
                    });
                    unoptimized-docker-image = lib.mkForce (
                        pkgs.dockerTools.buildImage {
                            name = "ihp-app";
                            copyToRoot =
                                with pkgs.dockerTools;
                                [
                                    usrBinEnv
                                    binSh
                                    caCertificates
                                ]
                                ++ [
                                    pkgs.bashInteractive
                                    pkgs.codex
                                    pkgs.coreutils
                                    pkgs.curl
                                    pkgs.git
                                    pkgs.just
                                    pkgs.rsync
                                    pkgs.scaleway-cli
                                ];
                            config = {
                                Cmd = [ "${self'.packages.unoptimized-prod-server}/bin/RunProdServer" ];
                                WorkingDir = "/app";
                                Env = [
                                    "PATH=/app/bin:${pkgs.codex}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.git}/bin:${pkgs.just}/bin:${pkgs.rsync}/bin:${pkgs.scaleway-cli}/bin:/usr/bin:/bin"
                                    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                    "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                    "SSL_CERT_DIR=/etc/ssl/certs"
                                ];
                            };
                            extraCommands = ''
                                ${dockerImageEtcCommands}

                                mkdir -p app/bin app/build/bin
                                ln -sf ${pkgs.codex}/bin/codex app/bin/codex
                                ln -sf ${pkgs.curl}/bin/curl app/bin/curl
                                ln -sf ${pkgs.git}/bin/git app/bin/git
                                ln -sf ${pkgs.just}/bin/just app/bin/just
                                ln -sf ${pkgs.rsync}/bin/rsync app/bin/rsync
                                ln -sf ${pkgs.scaleway-cli}/bin/scw app/bin/scw
                                ln -sf ${self'.packages.unoptimized-prod-server}/bin/RunProdServer app/bin/RunProdServer
                                cat > app/bin/RunJobs <<'EOF'
#!/bin/sh
set -e

if [ -x "${self'.packages.unoptimized-prod-server}/bin/RunJobs" ]; then
  exec "${self'.packages.unoptimized-prod-server}/bin/RunJobs" "$@"
fi

for f in /nix/store/*/bin/RunJobs; do
  if [ -x "$f" ]; then
    exec "$f" "$@"
  fi
done

echo "RunJobs binary not found in image" >&2
exit 127
EOF
                                chmod +x app/bin/RunJobs
                                ln -sf ../bin/RunJobs app/build/bin/RunJobs
                                ln -sfn ${self'.packages.static} app/static
                            '';
                        }
                    );
                    "migrate-docker-image" = pkgs.dockerTools.buildImage {
                        name = "ihp-migrate";
                        copyToRoot =
                            with pkgs.dockerTools;
                            [
                                usrBinEnv
                                binSh
                                caCertificates
                            ]
                            ++ [
                                pkgs.coreutils
                            ];
                        config = {
                            Cmd = [ "${self'.packages.migrate}/bin/migrate" ];
                            Env = [
                                "PATH=${pkgs.coreutils}/bin:/usr/bin:/bin"
                                "IHP_MIGRATION_DIR=${config.ihp.projectPath}/Application/Migration/"
                                "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                "SSL_CERT_DIR=/etc/ssl/certs"
                            ];
                        };
                    };
                    "git-ssh-docker-image" = pkgs.dockerTools.buildImage {
                        name = "ihp-git-ssh";
                        copyToRoot =
                            with pkgs.dockerTools;
                            [
                                usrBinEnv
                                binSh
                                caCertificates
                            ]
                            ++ [
                                pkgs.bashInteractive
                                pkgs.coreutils
                                pkgs.curl
                                pkgs.git
                                pkgs.gawk
                                pkgs.gnused
                                pkgs.openssh
                                pkgs.postgresql
                            ];
                        config = {
                            Cmd = [ "/app/bin/RunGitSshd" ];
                            WorkingDir = "/app";
                            Env = [
                                "PATH=/app/bin:${pkgs.bashInteractive}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.git}/bin:${pkgs.gawk}/bin:${pkgs.gnused}/bin:${pkgs.openssh}/bin:${pkgs.postgresql}/bin:/usr/bin:/bin"
                                "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
                                "SSL_CERT_DIR=/etc/ssl/certs"
                            ];
                        };
                        extraCommands = ''
                            ${dockerImageEtcCommands}

                            mkdir -p app/bin app/scripts
                            cp ${./scripts/gitWiggum-ssh-shell.sh} app/scripts/gitWiggum-ssh-shell.sh
                            cp ${./scripts/k8s/git-ssh-entrypoint.sh} app/scripts/git-ssh-entrypoint.sh
                            chmod +x app/scripts/gitWiggum-ssh-shell.sh app/scripts/git-ssh-entrypoint.sh
                            cat > app/bin/RunGitSshd <<'EOF'
#!/bin/sh
set -e
exec /app/scripts/git-ssh-entrypoint.sh "$@"
EOF
                            chmod +x app/bin/RunGitSshd
                        '';
                    };
                };

                devenv.shells.default = {
                    process.managers.process-compose.tui.enable = false;
                    env = {
                        PGDATABASE = "app";
                        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
                        SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";
                        NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
                    };
                    packages = with pkgs; [
                        age
                        awscli2
                        cacert
                        codex
                        curl
                        just
                        mailhog
                        minio
                        openapi-generator-cli
                        sops
                        stripe-cli
                    ];
                    scripts.start-with-ngrok.exec = ''
                        set -euo pipefail

                        ${syncSharedSecretsScript}

                        mkdir -p \
                            ./data/repositories \
                            ./data/workflow-logs \
                            ./data/prompt-pr-logs \
                            ./data/ssh

                        export PATH="${config.devenv.shells.default.languages.haskell.package}/bin:${pkgs.haskellPackages.ghc}/bin:$PATH"

                        if [ -x ./scripts/install-hooks.sh ]; then
                            if ! ./scripts/install-hooks.sh --quiet; then
                                echo "Warning: automatic managed hook installation failed. Run 'direnv exec . just install-hooks' after the dev environment is healthy." >&2
                            fi
                        fi

                        if [ "''${NGROK_ENABLED:-0}" = "1" ] && [ -z "''${IHP_BASEURL:-}" ]; then
                            export IHP_BASEURL="$(ngrok-url)"
                            echo "Resolved ngrok base URL: $IHP_BASEURL"
                        fi

                        exec start
                    '';
                    scripts.ngrok-url.exec = ngrokUrlScript;
                    processes.ihp.exec = lib.mkForce "start-with-ngrok";
                    processes.git-ssh.exec = ''
                        set -euo pipefail

                        ssh_enabled="''${gitWiggum_SSH_ENABLED:-''${GITOKU_SSH_ENABLED:-1}}"

                        if [ "$ssh_enabled" = "0" ]; then
                            echo "SSH disabled; git-ssh process skipped"
                            exec sleep infinity
                        fi

                        repo_root="$(pwd)"
                        ssh_data_root="''${gitWiggum_SSH_DATA_ROOT:-''${GITOKU_SSH_DATA_ROOT:-}}"
                        ssh_user="''${gitWiggum_SSH_USER:-''${GITOKU_SSH_USER:-''${USER:-git}}}"
                        ssh_port="''${gitWiggum_SSH_PORT:-''${GITOKU_SSH_PORT:-2222}}"

                        if [ -z "$ssh_data_root" ]; then
                            echo "No SSH data root configured; git-ssh process skipped"
                            exec sleep infinity
                        fi

                        case "$ssh_data_root" in
                            /*) ;;
                            *) ssh_data_root="$repo_root/$ssh_data_root" ;;
                        esac

                        host_key="$ssh_data_root/ssh_host_ed25519_key"
                        authorized_keys="$ssh_data_root/authorized_keys"
                        config_file="$ssh_data_root/sshd_config"

                        mkdir -p "$ssh_data_root"
                        chmod 700 "$ssh_data_root"
                        touch "$authorized_keys"
                        chmod 600 "$authorized_keys"

                        if [ ! -f "$host_key" ]; then
                            ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$host_key"
                        fi

                        chmod 600 "$host_key"

                        printf "%s\n" \
                            "AllowAgentForwarding no" \
                            "AllowTcpForwarding no" \
                            "AllowUsers $ssh_user" \
                            "AuthorizedKeysFile $authorized_keys" \
                            "ChallengeResponseAuthentication no" \
                            "HostKey $host_key" \
                            "KbdInteractiveAuthentication no" \
                            "ListenAddress 0.0.0.0" \
                            "PasswordAuthentication no" \
                            "PermitRootLogin no" \
                            "PermitTTY no" \
                            "PidFile $ssh_data_root/sshd.pid" \
                            "Port $ssh_port" \
                            "PrintMotd no" \
                            "PubkeyAuthentication yes" \
                            "StrictModes no" \
                            "X11Forwarding no" \
                            > "$config_file"

                        echo "Starting Git SSH on $ssh_user@localhost:$ssh_port"
                        exec ${pkgs.openssh}/bin/sshd -D -e -f "$config_file"
                    '';
                    processes.ngrok.exec = ''
                        set -euo pipefail

                        ${syncSharedSecretsScript}

                        if [ "''${NGROK_ENABLED:-0}" != "1" ]; then
                            echo "NGROK_ENABLED is not set; ngrok process disabled"
                            exit 0
                        fi

                        if ! command -v ngrok >/dev/null 2>&1; then
                            echo "ngrok is required on PATH when NGROK_ENABLED=1"
                            exit 1
                        fi

                        args=(http "http://127.0.0.1:''${PORT:-8000}" --log=stdout)

                        if [ -n "''${NGROK_AUTHTOKEN:-}" ]; then
                            args+=(--authtoken "''${NGROK_AUTHTOKEN}")
                        fi

                        if [ -n "''${NGROK_DOMAIN:-}" ]; then
                            args+=(--domain="''${NGROK_DOMAIN}")
                        fi

                        exec ngrok "''${args[@]}"
                    '';
                    processes.minio.exec = ''
                        set -euo pipefail

                        repo_root="$(pwd)"
                        minio_api_port="''${MINIO_API_PORT:-9100}"
                        minio_console_port="''${MINIO_CONSOLE_PORT:-9001}"
                        minio_data_root="$repo_root/.devenv/state/minio/data"

                        mkdir -p "$minio_data_root"

                        echo "Starting MinIO on http://127.0.0.1:$minio_api_port"
                        exec ${pkgs.minio}/bin/minio server "$minio_data_root" \
                            --address "127.0.0.1:$minio_api_port" \
                            --console-address "127.0.0.1:$minio_console_port"
                    '';
                    processes.minio-init.exec = ''
                        set -euo pipefail

                        endpoint="''${AWS_ENDPOINT:-http://127.0.0.1:9100}"
                        bucket="''${gitWiggum_PR_UPLOADS_BUCKET:-''${GITOKU_PR_UPLOADS_BUCKET:-gitoku-pr-uploads}}"
                        public_base_url="''${gitWiggum_PR_UPLOADS_PUBLIC_BASE_URL:-''${GITOKU_PR_UPLOADS_PUBLIC_BASE_URL:-''${endpoint%/}/$bucket}}"
                        export AWS_ACCESS_KEY_ID="''${AWS_ACCESS_KEY_ID:-''${MINIO_ROOT_USER:-gitWiggum}}"
                        export AWS_SECRET_ACCESS_KEY="''${AWS_SECRET_ACCESS_KEY:-''${MINIO_ROOT_PASSWORD:-gitWiggum-local-dev-password}}"
                        export AWS_REGION="''${AWS_REGION:-us-east-1}"
                        export AWS_EC2_METADATA_DISABLED="true"
                        export AWS_PAGER=""

                        for _attempt in $(seq 1 60); do
                            if ${pkgs.curl}/bin/curl --silent --fail "$endpoint/minio/health/live" >/dev/null 2>&1; then
                                break
                            fi
                            sleep 1
                        done

                        ${pkgs.curl}/bin/curl --silent --fail "$endpoint/minio/health/live" >/dev/null

                        if ! ${pkgs.awscli2}/bin/aws --endpoint-url "$endpoint" s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
                            ${pkgs.awscli2}/bin/aws --endpoint-url "$endpoint" s3api create-bucket --bucket "$bucket" >/dev/null
                        fi

                        policy_file="$(mktemp)"
                        printf '%s' \
                            "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAnonymousRead\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":[\"s3:GetObject\"],\"Resource\":[\"arn:aws:s3:::$bucket/*\"]}]}" \
                            > "$policy_file"

                        ${pkgs.awscli2}/bin/aws --endpoint-url "$endpoint" s3api put-bucket-policy --bucket "$bucket" --policy "file://$policy_file" >/dev/null
                        rm -f "$policy_file"

                        echo "MinIO bucket $bucket is ready at $public_base_url"
                        exec sleep infinity
                    '';
                    processes.mailhog.exec = ''
                        set -euo pipefail

                        smtp_host="''${SMTP_HOST:-127.0.0.1}"
                        smtp_port="''${SMTP_PORT:-1025}"
                        mailhog_ui_port="''${MAILHOG_UI_PORT:-8025}"

                        echo "Starting MailHog on http://$smtp_host:$mailhog_ui_port"
                        exec ${pkgs.mailhog}/bin/MailHog \
                            -api-bind-addr "$smtp_host:$mailhog_ui_port" \
                            -ui-bind-addr "$smtp_host:$mailhog_ui_port" \
                            -smtp-bind-addr "$smtp_host:$smtp_port"
                    '';
                    processes.stripe-listen.exec = ''
                        set -euo pipefail

                        ${syncSharedSecretsScript}

                        stripe_secret_key="''${STRIPE_SECRET_KEY:-}"

                        if [ -z "$stripe_secret_key" ]; then
                            echo "STRIPE_SECRET_KEY missing; stripe-listen disabled"
                            exec sleep infinity
                        fi

                        if ! command -v stripe >/dev/null 2>&1; then
                            echo "Stripe CLI missing; stripe-listen disabled"
                            exec sleep infinity
                        fi

                        app_port="''${PORT:-8000}"
                        exec stripe listen --api-key "$stripe_secret_key" --forward-to "http://127.0.0.1:$app_port/StripeWebhook"
                    '';
                };
            };

            # Adding the new NixOS configuration for "production"
            # See https://ihp.digitallyinduced.com/Guide/deployment.html#deploying-with-deploytonixos for more info
            # Used to deploy the IHP application
            flake.nixosConfigurations."production" = import ./Config/nix/hosts/production/host.nix { inherit inputs; };
        };

    # The following configuration speeds up build times by using the devenv, cachix and digitallyinduced binary caches
    # You can add your own cachix cache here to speed up builds. For that uncomment the following lines and replace `CHANGE-ME` with your cachix cache name
    nixConfig = {
        extra-substituters = [
            "https://devenv.cachix.org"
            "https://cachix.cachix.org"
            "https://digitallyinduced.cachix.org"
            # "https://CHANGE-ME.cachix.org"
        ];
        extra-trusted-public-keys = [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
            "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
            # "CHANGE-ME.cachix.org-1:CHANGE-ME-PUBLIC-KEY"
        ];
    };
}
