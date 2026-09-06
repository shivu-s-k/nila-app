#!/usr/bin/env bash
#
# Runs LOCALLY. Copies the working tree to the EC2 instance and bootstraps it.
#
#   EC2_HOST=1.2.3.4 EC2_KEY=~/mykey.pem ./deploy/aws/deploy.sh
#
# Optional:
#   EC2_USER=ubuntu     # default: ec2-user (use `ubuntu` for Ubuntu AMIs)
#
set -euo pipefail

cd "$(dirname "$0")/../.."

: "${EC2_HOST:?Set EC2_HOST to the public IP or DNS name of the instance}"
: "${EC2_KEY:?Set EC2_KEY to the path of the .pem key for the instance}"
EC2_USER="${EC2_USER:-ec2-user}"

if [ ! -f "${EC2_KEY}" ]; then
    echo "Key not found: ${EC2_KEY}" >&2
    exit 1
fi
chmod 600 "${EC2_KEY}"

SSH=(ssh -i "${EC2_KEY}" -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}")

echo "==> Checking connectivity to ${EC2_USER}@${EC2_HOST}"
"${SSH[@]}" 'echo "    connected: $(hostname)"'

echo "==> Copying the application"
"${SSH[@]}" 'sudo mkdir -p /opt/mytemplate && sudo chown -R $(whoami) /opt/mytemplate'

# Ship the tracked tree only -- no local virtualenv, no reports, no .git.
git archive --format=tar HEAD \
    | "${SSH[@]}" 'tar -x -C /opt/mytemplate'

echo "==> Bootstrapping the instance (this takes a few minutes on first run)"
"${SSH[@]}" "sudo APP_USER=${EC2_USER} bash /opt/mytemplate/deploy/aws/bootstrap.sh"

echo
echo "==> Verifying from the outside"
if curl -fsS -o /dev/null -w '    HTTP %{http_code}\n' "http://${EC2_HOST}/"; then
    echo
    echo "Live: http://${EC2_HOST}/"
else
    echo
    echo "The app is running on the box but is not reachable from here." >&2
    echo "Check the security group allows inbound TCP 80 from your IP." >&2
    exit 1
fi
