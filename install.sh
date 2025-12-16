#!/bin/bash
# Show-Off Server Installer - javított / robusztus verzió
# Debian / Ubuntu / VirtualBox

set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

############################################
# KONFIG
############################################
CONFIG_FILE="./config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  echo "WARN: config.conf nem található, alapértelmezett értékekkel futok."
fi

: "${DRY_RUN:=false}"
: "${INSTALL_APACHE:=true}"
: "${INSTALL_SSH:=true}"
: "${INSTALL_NODE_RED:=true}"
: "${INSTALL_MOSQUITTO:=true}"
: "${INSTALL_MARIADB:=true}"
: "${INSTALL_PHP:=true}"
: "${INSTALL_UFW:=true}"
: "${LOGFILE:=/var/log/showoff_installer.log}"

############################################
# SZÍNEK
############################################
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

############################################
# ROOT CHECK
############################################
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo -e "${RED}Root jogosultság szükséges.${NC}"; exit 1
fi

############################################
# LOG
############################################
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

log() { echo "$(date '+%F %T') | $1" >> "$LOGFILE"; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; log "OK: $1"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; log "WARN: $1"; }
fail() { echo -e "${RED}✖ $1${NC}"; log "FAIL: $1"; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    warn "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

############################################
# BANNER
############################################
clear
cat << "EOF"
=========================================
  SHOW-OFF SERVER INSTALLER vFINAL (FIXED)
=========================================
EOF

echo -e "${BLUE}Logfile:${NC} $LOGFILE"

############################################
# EREDMÉNYEK
############################################
declare -A RESULTS
set_result() { RESULTS["$1"]="$2"; }

############################################
# APT HELPERS
############################################
apt_update() { run apt-get update -y; }
apt_install() { run apt-get install -y "$@"; }

############################################
# SAFE STEP
############################################
safe_step() {
  local label="$1"; shift
  if [[ "$DRY_RUN" == "true" ]]; then
    set_result "$label" "DRY-RUN"
    warn "$label DRY-RUN"
    return 0
  fi

  log "START: $label"
  if "$@"; then
    set_result "$label" "SIKERES"
    return 0
  else
    set_result "$label" "HIBA"
    return 1
  fi
}

############################################
# TELEPÍTŐK
############################################
install_apache() {
  apt_install apache2 || return 1
  run systemctl enable --now apache2 || return 1
}

install_ssh() {
  apt_install openssh-server || return 1
  run systemctl enable --now ssh || return 1
}

install_mosquitto() {
  apt_install mosquitto mosquitto-clients || return 1
  run systemctl enable --now mosquitto || return 1
}

install_mariadb() {
  apt_install mariadb-server || return 1
  run systemctl enable --now mariadb || return 1
}

install_php() {
  apt_install php libapache2-mod-php php-mysql || return 1
  run systemctl restart apache2 || return 1
}

install_ufw() {
  apt_install ufw || return 1

  if systemctl is-active --quiet ssh; then
    run ufw allow OpenSSH
  else
    warn "SSH nem fut – OpenSSH szabály kihagyva"
  fi

  run ufw allow 80/tcp
  run ufw allow 1880/tcp
  run ufw allow 1883/tcp
  run ufw --force enable || return 1
}

install_node_red() {
  apt_install curl ca-certificates || return 1

  set +e
  curl -fsSL https://github.com/node-red/linux-installers/releases/latest/download/update-nodejs-and-nodered-deb \
    | bash -s -- --confirm-root
  set -e

  run systemctl daemon-reload

  for svc in nodered node-red; do
    if systemctl list-unit-files | grep -q "^$svc.service"; then
      run systemctl enable --now "$svc.service"
      break
    fi
  done

  command -v node-red >/dev/null 2>&1
}

############################################
# EXTRA: SHOW-OFF DASHBOARD (Apache)
############################################
create_dashboard() {
  local WEBROOT="/var/www/html"
  cat > "$WEBROOT/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="hu">
<head>
<meta charset="UTF-8">
<title>Show-Off Server</title>
<style>
body { font-family: Arial, sans-serif; background:#0f172a; color:#e5e7eb; padding:40px; }
h1 { color:#38bdf8; }
.card { background:#020617; border-radius:16px; padding:20px; margin:20px 0; box-shadow:0 0 25px rgba(56,189,248,0.2); }
.ok { color:#22c55e; }
.bad { color:#ef4444; }

/* EXTRA VIZUÁLIS ELEMEK */
.status-dot {
  display:inline-block;
  width:12px;
  height:12px;
  border-radius:50%;
  margin-right:8px;
}
.status-ok {
  background:#22c55e;
  box-shadow:0 0 10px #22c55e;
}
.status-bad {
  background:#ef4444;
  box-shadow:0 0 10px #ef4444;
}
.bar {
  background:#020617;
  border-radius:10px;
  overflow:hidden;
  margin-top:8px;
}
.bar-fill {
  height:10px;
  background:linear-gradient(90deg,#38bdf8,#22c55e);
  width:0%;
  animation: fill 1.5s forwards;
}
@keyframes fill { from { width:0%; } to { width:100%; } }
</style>
</head>
<body>
<h1>🚀 Show-Off Server Dashboard</h1>
<div class="card">
<b>Hostname:</b> $(hostname)<br>
<b>OS:</b> $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')<br>
<b>Kernel:</b> $(uname -r)<br>
<b>Dátum:</b> $(date)
</div>
<div class="card">
<h2>Szolgáltatások</h2>
<ul>
<li><span class="status-dot $(systemctl is-active --quiet apache2 && echo status-ok || echo status-bad)"></span>Apache: <b>$(systemctl is-active apache2)</b><div class="bar"><div class="bar-fill"></div></div></li>
<li><span class="status-dot $(systemctl is-active --quiet ssh && echo status-ok || echo status-bad)"></span>SSH: <b>$(systemctl is-active ssh)</b><div class="bar"><div class="bar-fill"></div></div></li>
<li><span class="status-dot $(systemctl is-active --quiet mosquitto && echo status-ok || echo status-bad)"></span>Mosquitto: <b>$(systemctl is-active mosquitto)</b><div class="bar"><div class="bar-fill"></div></div></li>
<li><span class="status-dot $(systemctl is-active --quiet mariadb && echo status-ok || echo status-bad)"></span>MariaDB: <b>$(systemctl is-active mariadb)</b><div class="bar"><div class="bar-fill"></div></div></li>
<li><span class="status-dot $(systemctl is-active --quiet nodered && echo status-ok || echo status-bad)"></span>Node-RED: <b>$(systemctl is-active nodered 2>/dev/null)</b><div class="bar"><div class="bar-fill"></div></div></li>
</ul>
</div>
<div class="card">
<h2>Portok</h2>
<pre>$(ss -tulpn | grep -E '(:80|:1880|:1883)' || echo 'Nincs aktív port')</pre>
</div>
</body>
</html>
EOF
}

############################################
# FUTTATÁS
############################################
apt_update || warn "APT update sikertelen"

run_install() {
  local var="$1" label="$2" func="$3"
  echo -e "${BLUE}==> $label${NC}"

  if [[ "${!var}" == "true" ]]; then
    safe_step "$label" "$func" && ok "$label OK" || fail "$label HIBA"
  else
    set_result "$label" "KIHAGYVA"
    warn "$label kihagyva"
  fi
  echo
}

run_install INSTALL_APACHE    "Apache2"   install_apache
run_install INSTALL_SSH       "SSH"       install_ssh
run_install INSTALL_MOSQUITTO "Mosquitto" install_mosquitto
run_install INSTALL_NODE_RED  "Node-RED"  install_node_red
run_install INSTALL_MARIADB   "MariaDB"   install_mariadb
run_install INSTALL_PHP       "PHP"       install_php
run_install INSTALL_UFW       "UFW"       install_ufw

############################################
# ÖSSZEFOGLALÓ
############################################
ORDER=("Apache2" "SSH" "Mosquitto" "Node-RED" "MariaDB" "PHP" "UFW")

echo "================================="
for k in "${ORDER[@]}"; do
  echo "$k : ${RESULTS[$k]:-N/A}"
done

exit 0
