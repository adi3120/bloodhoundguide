#!/usr/bin/env bash
set -euo pipefail

dc="${1:-192.168.112.70}"
username="${2:-stephanie}"
domain="${3:-corp.com}"
work="${TMPDIR:-/tmp}/netexec-bhce-collector"
pkg_root="$work/package"
config_root="$work/nxc"
output_root="$work/output"

mkdir -p "$work" "$config_root" "$output_root"

if [[ ! -d "$pkg_root/usr/lib/python3/dist-packages/bloodhound_ce" ]]; then
  (
    cd "$work"
    apt download bloodhound-ce-python
  )
  deb="$(find "$work" -maxdepth 1 -type f -name 'bloodhound-ce-python_*.deb' -print -quit)"
  [[ -n "$deb" ]] || { echo "Could not find the downloaded bloodhound-ce-python package." >&2; exit 1; }
  rm -rf "$pkg_root"
  dpkg-deb -x "$deb" "$pkg_root"
fi

module_root="$pkg_root/usr/lib/python3/dist-packages"
if [[ ! -e "$module_root/bloodhound" ]]; then
  ln -s bloodhound_ce "$module_root/bloodhound"
fi

[[ -f "$HOME/.nxc/nxc.conf" ]] || { echo "Run netexec once so $HOME/.nxc/nxc.conf exists." >&2; exit 1; }
cp "$HOME/.nxc/nxc.conf" "$config_root/nxc.conf"
python3 - "$config_root/nxc.conf" <<'PY'
import configparser
import sys

path = sys.argv[1]
config = configparser.ConfigParser()
config.read(path)
if not config.has_section("BloodHound-CE"):
    config.add_section("BloodHound-CE")
config.set("BloodHound-CE", "bhce_enabled", "True")
with open(path, "w", encoding="utf-8") as handle:
    config.write(handle)
PY

read -rsp "Password for ${domain}\\${username}: " bh_password
echo
trap 'unset bh_password' EXIT

(
  cd "$output_root"
  NXC_PATH="$config_root" \
  PYTHONPATH="$module_root${PYTHONPATH:+:$PYTHONPATH}" \
    netexec ldap "$dc" \
      -u "$username" -d "$domain" -p "$bh_password" \
      --dns-server "$dc" --bloodhound -c All
)

zip_path="$(find "$config_root/logs" "$output_root" -maxdepth 1 -type f -name '*_bloodhound.zip' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
[[ -n "$zip_path" ]] || { echo "Collection finished, but no BloodHound ZIP was found." >&2; exit 1; }

echo "BloodHound CE ZIP: $zip_path"
sha256sum "$zip_path"
