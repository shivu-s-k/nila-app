#!/usr/bin/env bash
#
# Runs ON the EC2 instance. Installs system packages, builds the virtualenv,
# seeds the database and wires up gunicorn behind nginx.
#
# Safe to re-run: it is the same script for the first deploy and every one
# after, so there is no separate "update" path to drift out of sync.
#
#   sudo APP_USER=ec2-user bash /opt/mytemplate/deploy/aws/bootstrap.sh
#
set -euo pipefail

APP_DIR=/opt/mytemplate
APP_USER="${APP_USER:-ec2-user}"
ENV_FILE=/etc/mytemplate.env

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo." >&2
    exit 1
fi

echo "==> Installing system packages"
if command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 python3-pip nginx gcc python3-devel
elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 python3-pip nginx gcc python3-devel
elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y python3 python3-venv python3-pip nginx gcc python3-dev
else
    echo "No supported package manager found (dnf/yum/apt-get)." >&2
    exit 1
fi

echo "==> Building the virtualenv"
cd "${APP_DIR}"
python3 -m venv env
env/bin/python -m pip install --upgrade pip --quiet
# Playwright and the linters are build-time tooling; the server does not need them.
grep -viE '^(pytest|ruff|bandit)' requirements.txt > /tmp/requirements-runtime.txt
env/bin/python -m pip install -r /tmp/requirements-runtime.txt --quiet

echo "==> Generating secrets"
# Written once and preserved across re-runs, so sessions survive a redeploy.
if [ ! -f "${ENV_FILE}" ]; then
    SECRET=$(env/bin/python -c "import os,binascii;print(binascii.hexlify(os.urandom(26)).decode())")
    cat > "${ENV_FILE}" <<EOF
SECRET_KEY=${SECRET}
APPNAME_ENV=deploy
EOF
    chmod 600 "${ENV_FILE}"
    echo "    wrote ${ENV_FILE}"
else
    echo "    ${ENV_FILE} already exists, keeping it"
fi

echo "==> Preparing the database"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
if [ ! -f "${APP_DIR}/mytemplate.db" ]; then
    sudo -u "${APP_USER}" env APPNAME_ENV=deploy \
        "${APP_DIR}/env/bin/python" "${APP_DIR}/manage.py" initdb
    echo "    database created"
else
    echo "    database already exists, leaving it alone"
fi

echo "==> Installing the gunicorn service"
sed "s/__APP_USER__/${APP_USER}/g" \
    "${APP_DIR}/deploy/aws/mytemplate.service" > /etc/systemd/system/mytemplate.service

echo "==> Installing the nginx site"
if [ -d /etc/nginx/conf.d ]; then
    rm -f /etc/nginx/conf.d/default.conf
    cp "${APP_DIR}/deploy/aws/nginx-mytemplate.conf" /etc/nginx/conf.d/mytemplate.conf
else
    rm -f /etc/nginx/sites-enabled/default
    cp "${APP_DIR}/deploy/aws/nginx-mytemplate.conf" /etc/nginx/sites-available/mytemplate
    ln -sf /etc/nginx/sites-available/mytemplate /etc/nginx/sites-enabled/mytemplate
fi
# nginx needs to traverse into /opt/mytemplate to serve static files.
chmod o+x /opt /opt/mytemplate
nginx -t

echo "==> Starting services"
systemctl daemon-reload
systemctl enable --now mytemplate
systemctl restart mytemplate
systemctl enable --now nginx
systemctl restart nginx

echo "==> Waiting for the app to answer"
for i in $(seq 1 20); do
    if curl -fsS -o /dev/null http://127.0.0.1/; then
        echo
        echo "Deployed. MyTemplate is serving on port 80."
        exit 0
    fi
    sleep 2
done

echo "App did not respond in time. Recent logs:" >&2
journalctl -u mytemplate -n 40 --no-pager >&2
exit 1
