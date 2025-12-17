#!/bin/bash
# SHOW-OFF SERVER INSTALLER vFINAL + MENU + MATH GUARD
# Debian / Ubuntu / VirtualBox

set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

############################################
# KONFIG
############################################
CONFIG_FILE="./config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || echo "WARN: config.conf nem található"

: "${DRY_RUN:=false}"
: "${AUTO_INSTALL:=false}"

: "${INSTALL_APACHE:=true}"
: "${INSTALL_SSH:=true}"
: "${INSTALL_NODE_RED:=true}"
: "${INSTALL_MOSQUITTO:=true}"
: "${INSTALL_MARIADB:=true}"
: "${INSTALL_PHP:=true}"
: "${INSTALL_PHPMYADMIN:=true}"
: "${INSTALL_UFW:=true}"

: "${LOGFILE:=/var/log/showoff_installer.log}"

############################################
# SZÍNEK
############################################
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"

############################################
# ROOT CHECK
############################################
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo -e "${RED}Root szükséges${NC}"; exit 1; }

############################################
# LOG
############################################
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

log()  { echo "$(date '+%F %T') | $1" >> "$LOGFILE"; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; log "OK: $1"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; log "WARN: $1"; }
fail() { echo -e "${RED}✖ $1${NC}"; log "FAIL: $1"; }

run() {
  [[ "$DRY_RUN" == "true" ]] && { warn "[DRY-RUN] $*"; return 0; }
  "$@"
}

############################################
# RANDOM MATEK FELADAT (LETÖLTÉS VÉDELEM)
############################################
MATH_OK=false

math_challenge() {
  [[ "$DRY_RUN" == "true" ]] && return 0
  [[ "$MATH_OK" == "true" ]] && return 0

  local a b op correct answer q
  a=$((RANDOM % 20 + 1))
  b=$((RANDOM % 20 + 1))
  op=$((RANDOM % 3))

  case "$op" in
    0) correct=$((a + b)); q="$a + $b" ;;
    1) correct=$((a - b)); q="$a - $b" ;;
    2) correct=$((a * b)); q="$a × $b" ;;
  esac

  echo
  echo "🧠 Biztonsági ellenőrzés"
  echo "   $q = ?"
  read -rp "Válasz: " answer

  [[ "$answer" == "$correct" ]] || {
    fail "Hibás válasz – telepítés megszakítva"
    exit 1
  }

  MATH_OK=true
  ok "Helyes válasz"
}

############################################
# BANNER
############################################
clear
cat << "EOF"
=========================================
 SHOW-OFF SERVER INSTALLER
=========================================
EOF
echo -e "${BLUE}Logfile:${NC} $LOGFILE"

############################################
# MENÜ
############################################
show_menu() {
  echo
  echo "1) Apache2"
  echo "2) SSH"
  echo "3) Mosquitto (MQTT)"
  echo "4) Node-RED"
  echo "5) MariaDB"
  echo "6) PHP"
  echo "7) phpMyAdmin"
  echo "8) UFW"
  echo "9) MINDEN telepítése"
  echo "0) Kilépés"
  read -rp "Választás (pl: 1 4 8 vagy 9): " MENU_SELECTION
}

reset_flags() {
  INSTALL_APACHE=false
  INSTALL_SSH=false
  INSTALL_MOSQUITTO=false
  INSTALL_NODE_RED=false
  INSTALL_MARIADB=false
  INSTALL_PHP=false
  INSTALL_PHPMYADMIN=false
  INSTALL_UFW=false
}

apply_selection() {
  reset_flags
  for c in $MENU_SELECTION; do
    case "$c" in
      1) INSTALL_APACHE=true ;;
      2) INSTALL_SSH=true ;;
      3) INSTALL_MOSQUITTO=true ;;
      4) INSTALL_NODE_RED=true ;;
      5) INSTALL_MARIADB=true ;;
      6) INSTALL_PHP=true ;;
      7) INSTALL_PHPMYADMIN=true ;;
      8) INSTALL_UFW=true ;;
      9)
        INSTALL_APACHE=true
        INSTALL_SSH=true
        INSTALL_MOSQUITTO=true
        INSTALL_NODE_RED=true
        INSTALL_MARIADB=true
        INSTALL_PHP=true
        INSTALL_PHPMYADMIN=true
        INSTALL_UFW=true ;;
      0) exit 0 ;;
    esac
  done
}

############################################
# APT HELPERS
############################################
apt_update() { run apt-get update; }
apt_install() {
  math_challenge
  run apt-get install -y "$@"
}

############################################
# SAFE STEP
############################################
declare -A RESULTS
safe_step() {
  local label="$1"; shift
  log "START: $label"
  if "$@"; then RESULTS["$label"]="SIKERES"; return 0
  else RESULTS["$label"]="HIBA"; return 1
  fi
}

############################################
# TELEPÍTŐK
############################################
install_apache()      { apt_install apache2 && run systemctl enable --now apache2; }
install_ssh()         { apt_install openssh-server && run systemctl enable --now ssh; }
install_mosquitto()   { apt_install mosquitto mosquitto-clients && run systemctl enable --now mosquitto; }
install_mariadb()     { apt_install mariadb-server && run systemctl enable --now mariadb; }
install_php()         { apt_install php libapache2-mod-php php-mysql && run systemctl restart apache2; }

install_phpmyadmin() {
  math_challenge
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
  apt_install phpmyadmin
  run systemctl reload apache2
}

install_node_red() {
  apt_install curl ca-certificates
  math_challenge
  curl -fsSL https://github.com/node-red/linux-installers/releases/latest/download/update-nodejs-and-nodered-deb | bash -s -- --confirm-root
  run systemctl daemon-reload
  systemctl enable --now nodered.service 2>/dev/null || true
}

install_ufw() {
  apt_install ufw
  run ufw allow OpenSSH
  run ufw allow 80/tcp
  run ufw allow 1880/tcp
  run ufw allow 1883/tcp
  run ufw --force enable
}

############################################
# FUTTATÁS
############################################
[[ "$AUTO_INSTALL" != "true" ]] && show_menu && apply_selection

apt_update || exit 1

run_install() {
  local var="$1" label="$2" func="$3"
  [[ "${!var}" == "true" ]] && safe_step "$label" "$func" && ok "$label" || warn "$label kihagyva"
}

run_install INSTALL_APACHE     "Apache2"     install_apache
run_install INSTALL_SSH        "SSH"         install_ssh
run_install INSTALL_MOSQUITTO  "Mosquitto"   install_mosquitto
run_install INSTALL_NODE_RED   "Node-RED"    install_node_red
run_install INSTALL_MARIADB    "MariaDB"     install_mariadb
run_install INSTALL_PHP        "PHP"         install_php
run_install INSTALL_PHPMYADMIN "phpMyAdmin"  install_phpmyadmin
run_install INSTALL_UFW        "UFW"         install_ufw

############################################
# ÖSSZEFOGLALÓ
############################################
echo "================================="
for k in Apache2 SSH Mosquitto Node-RED MariaDB PHP phpMyAdmin UFW; do
  echo "$k : ${RESULTS[$k]:-N/A}"
done
exit 0
