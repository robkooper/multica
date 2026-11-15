#!/usr/bin/env bash
# Set up a Multica server, daemon and coding CLIs on a blank Ubuntu VM.
# Run as your own sudo-capable account (not root). Safe to re-run.
#
#   ./setup-vm.sh install [domain]    packages, server, HTTPS, agent user and CLIs
#   ./setup-vm.sh lockdown            turn off open signup and workspace creation
#   ./setup-vm.sh lockdown-off        allow workspace creation again (to add a workspace)
#   ./setup-vm.sh daemon              GitHub setup and the daemon as a systemd user service
#   ./setup-vm.sh upgrade             back up the database, update the server and the
#                                     multica CLI, restart the daemon
#   ./setup-vm.sh mail                set up email from the SMTP_* variables below
#
# Between the steps you log in by hand (the script prints what to do). Optional
# environment: MULTICA_USER (default multica), MULTICA_DIR (default ~/multica),
# GIT_NAME and GIT_EMAIL for the agents' commits. Missing values are asked for
# when run from a terminal. install lets only GIT_EMAIL sign up (others need an
# invitation) and leaves workspace creation on until lockdown.
#
# Email (login codes and invitations; without it codes only appear in the backend
# log): set SMTP_HOST and SMTP_FROM_EMAIL for install or mail. Optional:
# SMTP_PORT (default 25), SMTP_USERNAME and SMTP_PASSWORD (empty for an
# unauthenticated relay), SMTP_TLS (starttls or implicit), SMTP_TLS_INSECURE,
# SMTP_EHLO_NAME (default the domain). For example, the campus relay:
#   SMTP_HOST=outbound-relays.techservices.illinois.edu SMTP_FROM_EMAIL=no-reply@illinois.edu \
#   SMTP_TLS_INSECURE=true ./setup-vm.sh mail
# shellcheck disable=SC2016  # as_mc strings expand as the agent user, not here
set -euo pipefail

MC_USER=${MULTICA_USER:-multica}
MC_DIR=${MULTICA_DIR:-$HOME/multica}
COMPOSE=(docker compose -f docker-compose.selfhost.yml)
CRON_TAG="# multica-setup"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ask VAR "question" [default]: keep VAR if set, else prompt on a terminal, else use the default
ask() {
  local reply
  [ -n "${!1:-}" ] && return
  if [ -t 0 ]; then
    read -rp "$2${3:+ [$3]}: " reply
    printf -v "$1" '%s' "${reply:-${3:-}}"
  else
    printf -v "$1" '%s' "${3:-}"
  fi
  [ -n "${!1}" ] || die "$2: no value given"
}

# Run a command as the agent user in a login shell with the CLIs on PATH
# Not sudo -i: it runs the command through a login shell that does not escape $,
# so variables in $1 would expand there (empty or wrong) before bash -c sees them.
as_mc() {
  (cd / && sudo -u "$MC_USER" -H env \
    PATH="/home/$MC_USER/.local/bin:/home/$MC_USER/.opencode/bin:/usr/local/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$MC_USER")" \
    bash -c 'cd ~ && eval "$1"' as_mc "$1")
}

# Docker works before re-login thanks to sg, which picks up the new group
dk() {
  if docker info >/dev/null 2>&1; then "$@"
  else sg docker -c "$(printf '%q ' "$@")"; fi
}

# Set KEY=VALUE in the server's .env, replacing an existing line
# (awk, not sed, so values with | & or \ such as passwords are written as is)
set_env() {
  local f=$MC_DIR/.env
  K=$1 V=$2 awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, k "=") == 1 { print k "=" v; done = 1; next } { print }
    END { if (!done) print k "=" v }' "$f" >"$f.tmp"
  cat "$f.tmp" >"$f" && rm -f "$f.tmp"
}

# Write the SMTP_* settings to .env when SMTP_HOST is set; returns 1 when it is not
configure_mail() {
  [ -n "${SMTP_HOST:-}" ] || return 1
  [ -n "${SMTP_FROM_EMAIL:-}" ] || die "SMTP_HOST is set, so SMTP_FROM_EMAIL is needed too"
  local domain
  domain=$(sed -n 's|^FRONTEND_ORIGIN=https://||p' "$MC_DIR/.env")
  say "Configuring email through $SMTP_HOST"
  set_env SMTP_HOST "$SMTP_HOST"
  set_env SMTP_PORT "${SMTP_PORT:-25}"
  set_env SMTP_USERNAME "${SMTP_USERNAME:-}"
  set_env SMTP_PASSWORD "${SMTP_PASSWORD:-}"
  set_env SMTP_FROM_EMAIL "$SMTP_FROM_EMAIL"
  set_env SMTP_TLS "${SMTP_TLS:-}"
  set_env SMTP_TLS_INSECURE "${SMTP_TLS_INSECURE:-false}"
  # the backend runs in a container, so its own hostname means nothing to a relay
  set_env SMTP_EHLO_NAME "${SMTP_EHLO_NAME:-${domain:-$(hostname -f)}}"
}

# Show which mail mode the backend started in
mail_status() {
  (cd "$MC_DIR" && dk "${COMPOSE[@]}" logs backend 2>&1) | grep -E 'EmailService' | tail -n 1
}

compose_up() { (cd "$MC_DIR" && dk "${COMPOSE[@]}" up -d); }

# The multica CLI goes to /usr/local/bin, installed from this account (with sudo)
install_multica_cli() {
  curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash -s -- >/dev/null
  echo "multica CLI: $(/usr/local/bin/multica --version 2>/dev/null | head -n1 || echo unknown)"
}

install_packages() {
  say "Installing packages"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  sudo apt-get install -y git make curl openssl jq ca-certificates
  if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
  fi
  sudo usermod -aG docker "$USER"
  sudo apt-get install -y caddy
  if ! command -v node >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
  fi
  sudo apt-get install -y nodejs gh
}

create_agent_user() {
  say "Creating Unix user $MC_USER for the agents"
  id "$MC_USER" >/dev/null 2>&1 || sudo adduser --disabled-password --gecos "" "$MC_USER"
  # starts the user's systemd instance at boot, needed for the daemon service
  sudo loginctl enable-linger "$MC_USER"
}

install_server() {
  local domain=$1
  say "Installing the Multica server in $MC_DIR"
  if [ -d "$MC_DIR/.git" ]; then
    git -C "$MC_DIR" pull --ff-only
  else
    git clone --depth 1 https://github.com/multica-ai/multica.git "$MC_DIR"
  fi
  (cd "$MC_DIR" && dk make selfhost)
  curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://localhost:8080/readyz; echo
  # On a first run the Makefile reads .env before it exists and exports its default
  # password, so PostgreSQL is initialized with that instead of the generated one
  # in .env, and every later "docker compose up" fails to log in. Set the database
  # password to the one in .env (a no-op when they already match).
  local pgpass
  pgpass=$(grep '^POSTGRES_PASSWORD=' "$MC_DIR/.env" | cut -d= -f2-)
  [[ $pgpass =~ ^[A-Za-z0-9]+$ ]] || die "unexpected POSTGRES_PASSWORD format in $MC_DIR/.env"
  # shellcheck disable=SC2016  # expanded inside the postgres container
  (cd "$MC_DIR" && dk "${COMPOSE[@]}" exec -T postgres sh -c \
    'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER USER \"$POSTGRES_USER\" PASSWORD '\''$1'\''"' \
    _ "$pgpass" </dev/null)

  say "Configuring Caddy for https://$domain"
  local caddy
  caddy=$(cat <<EOF
$domain {
    handle /health {
        reverse_proxy 127.0.0.1:8080
    }
    handle /ws {
        reverse_proxy 127.0.0.1:8080 {
            flush_interval -1
        }
    }
    handle /api/daemon/ws {
        reverse_proxy 127.0.0.1:8080 {
            flush_interval -1
        }
    }
    handle {
        reverse_proxy 127.0.0.1:3000
    }
}
EOF
)
  if ! cmp -s <(printf '%s\n' "$caddy") /etc/caddy/Caddyfile; then
    [ -f /etc/caddy/Caddyfile ] && sudo cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.$(date +%Y%m%d%H%M%S).bak"
    printf '%s\n' "$caddy" | sudo tee /etc/caddy/Caddyfile >/dev/null
    sudo systemctl reload caddy
  fi

  set_env FRONTEND_ORIGIN "https://$domain"
  set_env MULTICA_APP_URL "https://$domain"
  # Only the agents' git email can sign up; others need an invitation. Workspace
  # creation stays on until lockdown, so that person can create the first workspace.
  set_env ALLOW_SIGNUP false
  local allowed
  allowed=$(sed -n 's/^ALLOWED_EMAILS=//p' "$MC_DIR/.env")
  case ",$allowed," in
    *",$GIT_EMAIL,"*) ;;
    *) set_env ALLOWED_EMAILS "${allowed:+$allowed,}$GIT_EMAIL" ;;
  esac
  configure_mail || true
  # restart does not re-read .env; up -d does
  compose_up
  curl -fsS --retry 10 --retry-delay 3 --retry-all-errors "https://$domain/health" \
    || echo "warning: https://$domain/health is not reachable yet (DNS, ports 80/443 or the certificate)" >&2
  echo
}

install_clis() {
  local domain=$1
  say "Installing Claude Code, OpenCode, Codex and the multica CLI as $MC_USER"
  as_mc 'command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash'
  as_mc 'command -v opencode >/dev/null || curl -fsSL https://opencode.ai/install | bash'
  as_mc 'npm config set prefix ~/.local && npm install -g @openai/codex'
  # The agent user has no sudo, and the installer tries sudo for /usr/local/bin,
  # so install the multica CLI from this account; upgrade replaces it the same way
  install_multica_cli
  # uv runs the Python test suites, helm renders charts for review
  as_mc 'command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh'
  as_mc 'command -v helm >/dev/null || { mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | env HELM_INSTALL_DIR=$HOME/.local/bin USE_SUDO=false bash; }'
  as_mc 'claude --version && codex --version && opencode --version && uv --version && helm version --short && command -v multica' \
    || echo "warning: a CLI did not report its version" >&2

  say "Configuring the $MC_USER account"
  as_mc 'grep -q "opencode/bin" ~/.bashrc || echo '\''export PATH=$HOME/.local/bin:$HOME/.opencode/bin:$PATH'\'' >>~/.bashrc'
  as_mc 'grep -q XDG_RUNTIME_DIR ~/.bashrc || echo '\''export XDG_RUNTIME_DIR=/run/user/$(id -u)'\'' >>~/.bashrc'
  # keep Claude Code's co-author trailer out of commits and PRs
  as_mc 'mkdir -p ~/.claude && f=~/.claude/settings.json && { [ -s $f ] || echo "{}" >$f; } &&
    jq ".attribution = {commit: \"\", pr: \"\"}" $f >$f.tmp && mv $f.tmp $f'
  as_mc "multica config set server_url https://$domain && multica config set app_url https://$domain"
  as_mc "git config --global user.name $(printf '%q' "$GIT_NAME") && git config --global user.email $(printf '%q' "$GIT_EMAIL")"

  # Nightly updates; Codex does not update itself. Replaces the tagged block, and
  # the same lines added by hand without tags, so a re-run never duplicates them.
  local cron
  cron=$(cat <<EOF
PATH=/home/$MC_USER/.local/bin:/home/$MC_USER/.opencode/bin:/usr/local/bin:/usr/bin:/bin
30 3 * * * npm install -g @openai/codex@latest >> /home/$MC_USER/cli-update.log 2>&1
35 3 * * * claude update >> /home/$MC_USER/cli-update.log 2>&1
40 3 * * * opencode upgrade >> /home/$MC_USER/cli-update.log 2>&1
45 3 * * * uv self update >> /home/$MC_USER/cli-update.log 2>&1
EOF
)
  # Our block goes first so lines added by hand below it get its PATH
  as_mc "{ printf '%s\n' '$CRON_TAG begin' $(printf '%q' "$cron") '$CRON_TAG end'
  crontab -l 2>/dev/null | sed '/^$CRON_TAG begin/,/^$CRON_TAG end/d' | grep -vxF -f <(printf '%s\n' $(printf '%q' "$cron")) || true
} | crontab -"

  as_mc 'mkdir -p ~/.config/systemd/user && cat >~/.config/systemd/user/multica-daemon.service <<EOF
[Unit]
Description=Multica agent daemon

[Service]
WorkingDirectory=%h
Environment=PATH=%h/.local/bin:%h/.opencode/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$(command -v multica || echo %h/.local/bin/multica) daemon start --foreground
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF'
}

cmd_install() {
  [ $# -le 1 ] || die "usage: $0 install [domain]"
  [ "$(id -u)" -ne 0 ] || die "run as your own account, not root"
  local domain=${1:-} reply
  ask domain "Public DNS name for Multica" "$(hostname -f)"
  ask GIT_NAME "Git author name for agent commits" "$(git config --global user.name 2>/dev/null || true)"
  ask GIT_EMAIL "Git author email for agent commits" "$(git config --global user.email 2>/dev/null || true)"
  printf '\nDomain:      %s\nAgent user:  %s\nServer dir:  %s\nGit author:  %s <%s>\n' \
    "$domain" "$MC_USER" "$MC_DIR" "$GIT_NAME" "$GIT_EMAIL"
  if [ -t 0 ]; then
    read -rp "Continue? [Y/n] " reply
    [[ ${reply:-y} =~ ^[Yy] ]] || exit 1
  fi
  install_packages
  create_agent_user
  install_server "$domain"
  install_clis "$domain"
  cat <<EOF

Done. Next, by hand:

1. Open https://$domain, sign in as $GIT_EMAIL (the only address allowed to sign
   up; invite others from Settings -> Members) and create a workspace. Without
   email set up, the login code is in:
     cd $MC_DIR && docker compose -f docker-compose.selfhost.yml logs backend | grep "Verification code"
   (log out and back in first so docker works without sudo)
2. Run: $0 lockdown
3. Create an API token in Settings -> API Token, a fine-grained GitHub token
   (Contents and Pull requests read/write), then as $MC_USER (sudo -iu $MC_USER):
     claude                       # log in, then /exit
     codex login --device-auth
     opencode auth login
     gh auth login                # GitHub.com, HTTPS, paste the token
     multica login --token=       # paste the Multica API token
4. Run: $0 daemon
EOF
}

cmd_lockdown() {
  [ -f "$MC_DIR/.env" ] || die "$MC_DIR/.env not found; run install first"
  say "Turning off open signup and workspace creation"
  set_env ALLOW_SIGNUP false
  set_env DISABLE_WORKSPACE_CREATION true
  compose_up
  echo "To add a workspace later, set DISABLE_WORKSPACE_CREATION=false in $MC_DIR/.env or run: $0 lockdown-off"
}

cmd_lockdown_off() {
  [ -f "$MC_DIR/.env" ] || die "$MC_DIR/.env not found; run install first"
  set_env DISABLE_WORKSPACE_CREATION false
  compose_up
  echo "Workspace creation is on. Run $0 lockdown when done."
}

cmd_daemon() {
  as_mc 'gh auth status >/dev/null 2>&1' || die "gh is not logged in for $MC_USER; run gh auth login as $MC_USER"
  as_mc 'multica workspace list >/dev/null 2>&1' || die "multica is not logged in for $MC_USER; run multica login --token= as $MC_USER"
  as_mc 'git config --global user.email >/dev/null' \
    || die "the agents' git identity is not set; re-run $0 install, or git config --global as $MC_USER"

  say "Setting up git and gh stack for $MC_USER"
  as_mc 'gh auth setup-git'
  as_mc 'gh stack --help >/dev/null 2>&1 || gh extension install github/gh-stack'

  say "Starting the daemon as a systemd user service"
  as_mc 'multica daemon stop >/dev/null 2>&1 || true'
  as_mc 'systemctl --user daemon-reload && systemctl --user enable multica-daemon && systemctl --user restart multica-daemon'
  sleep 5
  as_mc 'systemctl --user --no-pager status multica-daemon | head -n 5; multica daemon status' || true
  cat <<EOF

The Runtimes page should show Claude Code, Codex and OpenCode on this machine.
Logs: sudo -iu $MC_USER journalctl --user -u multica-daemon -f
Then apply the agents from this repo: ./apply.sh <workspace> $(hostname)
EOF
}

cmd_mail() {
  [ -f "$MC_DIR/.env" ] || die "$MC_DIR/.env not found; run install first"
  configure_mail || die "set SMTP_HOST and SMTP_FROM_EMAIL (see $0 without arguments)"
  compose_up
  curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://localhost:8080/readyz >/dev/null
  mail_status
}

cmd_upgrade() {
  [ -f "$MC_DIR/.env" ] || die "$MC_DIR/.env not found; run install first"
  local backup_dir=$HOME/multica-backups backup
  mkdir -p "$backup_dir"
  backup="$backup_dir/multica-$(date +%Y%m%d-%H%M%S).sql.gz"
  say "Backing up the database to $backup (migrations only go forward)"
  # shellcheck disable=SC2016  # expanded inside the postgres container
  (cd "$MC_DIR" && dk "${COMPOSE[@]}" exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"') \
    | gzip >"$backup"
  [ "$(gzip -dc "$backup" | head -c 1 | wc -c)" -gt 0 ] || die "database backup is empty; not upgrading"

  say "Updating the multica CLI"
  install_multica_cli

  say "Updating the server"
  git -C "$MC_DIR" pull --ff-only --quiet
  (cd "$MC_DIR" && dk "${COMPOSE[@]}" pull && dk "${COMPOSE[@]}" up -d --remove-orphans)
  dk docker image prune -f
  curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://localhost:8080/readyz; echo

  say "Restarting the daemon"
  as_mc 'systemctl --user restart multica-daemon && systemctl --user --no-pager status multica-daemon | head -n 5'
}

case "${1:-}" in
  install) shift; cmd_install "$@" ;;
  lockdown) cmd_lockdown ;;
  lockdown-off) cmd_lockdown_off ;;
  daemon) cmd_daemon ;;
  upgrade) cmd_upgrade ;;
  mail) cmd_mail ;;
  *) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
