#!/usr/bin/env bash
# Standalone host Nginx only. Do not execute before inspecting the real host.
set -Eeuo pipefail
mode="${1:-full}"
[[ "$mode" == full || "$mode" == --stage-http ]] || { printf 'Unknown mode\n' >&2; exit 2; }

domain='suixiangji.icu'
www_domain='www.suixiangji.icu'
expected_ip='47.98.183.77'
base='/var/www/suixiangji-website'
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
release="$base/releases/$run_id"
backup="$base/backups/$run_id"
certificate="/etc/letsencrypt/live/$domain"

fail() { printf 'Deployment stopped: %s\n' "$*" >&2; exit 2; }
[[ "$(id -u)" == 0 ]] || fail 'Run with root / sudo after confirming server access.'
for executable in nginx python3 openssl curl systemctl; do
  command -v "$executable" >/dev/null || fail "Missing prerequisite: $executable"
done
[[ -d "$package_dir/site" && -f "$package_dir/manifest.json" ]] || fail 'Incomplete deployment package.'
nginx -t
systemctl is-active --quiet nginx || fail 'This helper requires active host Nginx.'

python3 - "$package_dir" "$expected_ip" "$domain" "$www_domain" "$mode" <<'PY'
import hashlib, json, socket, sys
from pathlib import Path
package = Path(sys.argv[1])
manifest = json.loads((package / 'manifest.json').read_text())
for name, expected in manifest['files'].items():
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts:
        raise SystemExit('Unsafe path in manifest')
    data = (package / 'site' / relative).read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit('File checksum mismatch: ' + name)
actual = {str(p.relative_to(package / 'site')) for p in (package / 'site').rglob('*') if p.is_file()}
if actual != set(manifest['files']):
    raise SystemExit('Unexpected or missing files in deployment package')
if sys.argv[-1] != '--stage-http':
    for domain in sys.argv[3:-1]:
        answers = {item[4][0] for item in socket.getaddrinfo(domain, 80, type=socket.SOCK_STREAM)}
        if answers != {sys.argv[2]}:
            raise SystemExit('DNS is not ready for ' + domain + ': ' + ', '.join(sorted(answers)))
    print('File checksums and both domain records verified.')
else:
    print('File checksums verified; DNS and HTTPS deferred during HTTP staging.')
PY

nginx_dump="$(nginx -T 2>/dev/null)"
conf_dir=''
if [[ "$nginx_dump" == *'include /etc/nginx/conf.d/*.conf;'* ]]; then
  conf_dir='/etc/nginx/conf.d'
elif [[ "$nginx_dump" == *'include /etc/nginx/sites-enabled/*;'* ]]; then
  conf_dir='/etc/nginx/sites-enabled'
else
  fail 'Unknown Nginx include layout; inspect and adapt before deployment.'
fi
conf="$conf_dir/suixiangji-website.conf"
[[ ! -L "$conf" ]] || fail 'Website config is a symlink; inspect before modifying.'
# Detect conflicting exact server names, without printing any full configuration.
NGINX_WEBSITE_DUMP="$nginx_dump" python3 - "$conf" "$domain" "$www_domain" <<'PY'
import os, re, sys
current = ''
for line in os.environ['NGINX_WEBSITE_DUMP'].splitlines():
    marker = re.match(r'^# configuration file (.+):$', line)
    if marker:
        current = marker.group(1)
    clean = line.split('#', 1)[0]
    match = re.search(r'\bserver_name\s+([^;]+);', clean)
    if match and set(sys.argv[2:]).intersection(match.group(1).split()) and current != sys.argv[1]:
        raise SystemExit('Domain is already configured in another file: ' + current)
PY
unset nginx_dump

certificate_ready=false
if [[ -f "$certificate/fullchain.pem" && -f "$certificate/privkey.pem" ]]; then
  if openssl x509 -in "$certificate/fullchain.pem" -checkend 604800 -noout >/dev/null &&
     openssl x509 -in "$certificate/fullchain.pem" -checkhost "$domain" -noout >/dev/null &&
     openssl x509 -in "$certificate/fullchain.pem" -checkhost "$www_domain" -noout >/dev/null; then
    certificate_ready=true
  fi
fi
if [[ "$certificate_ready" != true && "$mode" != --stage-http ]]; then
  command -v certbot >/dev/null || fail 'No valid target certificate and Certbot is unavailable.'
fi
[[ ! -e "$base/current" || -L "$base/current" ]] || fail 'Current website path is not a symlink.'
install -d -m 0755 "$release" "$base/acme" "$backup"
cp -a -- "$package_dir/site/." "$release/"
find "$release" -type d -exec chmod 0755 {} +
find "$release" -type f -exec chmod 0644 {} +
old_link=''
[[ ! -L "$base/current" ]] || old_link="$(readlink "$base/current")"
had_config=false
if [[ -f "$conf" ]]; then
  cp -p -- "$conf" "$backup/website.conf.before"
  had_config=true
fi
printf '%s\n' "$old_link" > "$backup/current.before"
rollback() {
  status=$?
  trap - ERR
  if [[ "$had_config" == true ]]; then cp -p -- "$backup/website.conf.before" "$conf"; else rm -f -- "$conf"; fi
  if [[ -n "$old_link" ]]; then
    ln -s -- "$old_link" "$base/.rollback-$run_id"
    mv -Tf -- "$base/.rollback-$run_id" "$base/current"
  elif [[ -L "$base/current" ]]; then rm -f -- "$base/current"; fi
  nginx -t && systemctl reload nginx
  printf 'Website changes rolled back. Retained evidence: %s\n' "$backup" >&2
  exit "$status"
}
trap rollback ERR
ln -s -- "$release" "$base/.current-$run_id"
mv -Tf -- "$base/.current-$run_id" "$base/current"

cat > "$backup/website-http.conf" <<EOF
server {
    listen 80;
    server_name $domain $www_domain;
    root $base/current;
    index index.html;
    location ^~ /.well-known/acme-challenge/ { root $base/acme; }
    location / { try_files \$uri \$uri/ =404; }
}
# Keep these unprovisioned HTTPS names from falling through to another site.
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain $www_domain;
    ssl_reject_handshake on;
    return 444;
}
EOF
install -m 0644 "$backup/website-http.conf" "$conf"
nginx -t
systemctl reload nginx
curl --fail --silent --show-error --max-time 10 --retry 5 --retry-delay 1 --retry-all-errors --retry-max-time 15 \
  --resolve "$domain:80:127.0.0.1" "http://$domain/" -o /dev/null
if [[ "$mode" == --stage-http ]]; then
  trap - ERR
  printf 'HTTP origin staged for %s; public DNS and HTTPS are pending.\nRelease: %s\nConfig: %s\nBackup: %s\n' "$domain" "$release" "$conf" "$backup"
  exit 0
fi
if [[ "$certificate_ready" != true ]]; then
  certbot certonly --webroot -w "$base/acme" --cert-name "$domain" \
    -d "$domain" -d "$www_domain" --non-interactive --agree-tos --register-unsafely-without-email
fi
cat > "$backup/website-https.conf" <<EOF
server {
    listen 80;
    server_name $domain $www_domain;
    location ^~ /.well-known/acme-challenge/ { root $base/acme; }
    location / { return 301 https://$domain\$request_uri; }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain $www_domain;
    ssl_certificate $certificate/fullchain.pem;
    ssl_certificate_key $certificate/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root $base/current;
    index index.html;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    if (\$host = $www_domain) { return 301 https://$domain\$request_uri; }
    location / { try_files \$uri \$uri/ =404; add_header Cache-Control "no-cache"; }
    location ^~ /.well-known/acme-challenge/ { root $base/acme; }
}
EOF
install -m 0644 "$backup/website-https.conf" "$conf"
nginx -t
systemctl reload nginx
# Nginx reload is asynchronous: allow the new workers to replace the pending TLS guard.
curl --fail --silent --show-error --max-time 10 --retry 5 --retry-delay 1 --retry-all-errors --retry-max-time 15 \
  --resolve "$domain:443:127.0.0.1" "https://$domain/" -o /dev/null
trap - ERR
printf 'Website deployed: https://%s/\nRelease: %s\nConfig: %s\nBackup: %s\n' "$domain" "$release" "$conf" "$backup"
