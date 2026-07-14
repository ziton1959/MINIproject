# 3-Tier Application Deployment with IaC — POC

A fully automated, security-hardened 3-tier environment (web, app, db) built with
Vagrant (provisioning) and Ansible (configuration), deploying a CRUD application
end to end.

## Architecture
                  Windows host (browser)
                          |
                  localhost:8080 (port forward)
                          v
+--------------+     +----------------+     +------------------+
|  WEB tier    | --> |   APP tier     | --> |    DB tier       |
|  nginx       |     |  Flask API     |     |  PostgreSQL      |
|  .56.10      |     |  .56.30:5000   |     |  .56.20:5432     |
|  ports 80/443|     |  internal only |     |  internal only   |
+--------------+     +----------------+     +------------------+
^                    ^                      ^
+--------- SSH (22) from control node ------+
CONTROL: 192.168.56.5 (runs Ansible)

Traffic policy (enforced by UFW, default deny incoming):
- Web tier: 80/443 open publicly; SSH from control only
- App tier: port 5000 reachable from the web tier only; SSH from control only
- DB tier: port 5432 reachable from the app tier only; SSH from control only

## Tool choices

The assignment's primary path used Terraform against AWS (Pluralsight). Per the
assignment's stated fallback, the environment was built locally with
**Vagrant-based virtual machines**, with Vagrant serving as the IaC provisioning
layer. The architecture is provider-agnostic: the entire Ansible layer is
unchanged between platforms; only the provisioning layer would swap for
Terraform (VPC, security groups, EC2) on AWS.

## How to run

Two commands reproduce the entire environment:
vagrant up                 # provision all 4 VMs (Windows host)
vagrant ssh control        # enter the control node
cd ~/iac && ./deploy.sh    # configure all tiers + deploy the app (one command)

Then open http://localhost:8080 in a browser.

Updating any infra/app configuration is one command: edit the relevant
role/template and re-run `./deploy.sh`. Runs are idempotent — a second
execution reports `changed=0` on all hosts.

## The application

A CRUD message board proving full-stack integration:
- **Create/Update/Delete** from the UI travel Web -> App -> DB and persist in PostgreSQL
- Survives page refresh and VM reboot (state lives in the DB tier only)
- All queries parameterized (SQL-injection safe); input validated server-side

## Security implementation

- **SSH hardening** (all tiers): root login disabled, password authentication
  disabled, key-based auth only — verified: password SSH attempts are refused
  with `Permission denied (publickey)`.
- **Firewall** (UFW, all tiers): default deny incoming; per-tier allow rules
  exactly matching the traffic policy above; SSH restricted to the control
  node's IP (stricter than required).
- **Database**: bound to localhost + internal IP only (never 0.0.0.0);
  pg_hba grants access to the app user from the app tier's IP only;
  app user has least-privilege grants (DML on specific tables, no DDL).
- **API**: runs as a dedicated no-login system user (not root); bound to the
  internal interface only; managed by systemd with auto-restart.

### Verified isolation (sample evidence)
web -> db:5432   BLOCKED     (firewall denies Web->DB)
app -> db:5432   OPEN        (allowed path)
db  -> app:5000  BLOCKED     (reverse path denied)

### Security incident note

During development, per-VM Vagrant bootstrap SSH keys were accidentally
committed. Remediation: keys untracked, history rewritten, offending branch
deleted, `.gitignore` added. Practical exposure was nil — the keys grant access
only to a host-only network unreachable from outside the development machine.

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs on every push:
playbook syntax check + ansible-lint. See the Actions tab for green runs.

## Repository structure
Vagrantfile            # IaC: provisions control, web, app, db VMs
deploy.sh              # one-command configuration + deployment
site.yml               # master playbook mapping roles to tiers
inventory/hosts.ini    # tier IPs and connection settings
group_vars/all.yml     # shared variables (IPs, ports, DB settings)
roles/
common/              # base packages, timezone
ssh-hardening/       # root login off, key-only auth
firewall/            # per-tier UFW rules
database/            # PostgreSQL, schema, least-privilege user
backend/             # Flask CRUD API as a systemd service
frontend/            # nginx UI + reverse proxy to the API
.github/workflows/     # CI pipeline

## Possible improvements

Ansible Vault for the DB password, automated validation playbook, load
balancing / HA for the web tier, monitoring (Prometheus/node_exporter),
containerization of the app tier.
