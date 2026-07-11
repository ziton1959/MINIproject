#!/usr/bin/env bash
# One-command deployment: configures all tiers and deploys the app.
set -e
cd "$(dirname "$0")"
ansible-playbook site.yml
