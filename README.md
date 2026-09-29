# Reproducible Linux baseline (OpenTofu + cloud-init + Ansible)

A disposable VPS you can destroy and rebuild from source, with nothing configured by hand.

This repo exists because "reproducible" usually means "it worked on my machine once". Here the claim is narrower and testable: delete the server, run two commands, and you get the same hardened box back, with evidence written to disk proving it.

Everything here runs against throwaway infrastructure with synthetic data. No production credentials, no customer data.

## What it builds

A single Ubuntu 24.04 VPS with:

- Cloud firewall and SSH key registered through OpenTofu on AWS, Hetzner or DigitalOcean, chosen by one variable
- A minimal cloud-init first boot, just enough for Ansible to take over
- Baseline hardening: SSH drop-in config, UFW, fail2ban, unattended upgrades, sysctl
- Docker from the official repository with log rotation and `no-new-privileges`
- Tailscale, with public SSH closed once the tailnet is confirmed up
- restic backups to an off-host repository, on a systemd timer, with a restore test you can run
- A health check timer with a dead man's switch, so silence is treated as failure

## Layout

    tofu/                 provider-neutral root module, one submodule per provider
    cloud-init/           first boot template, deliberately small
    ansible/roles/        baseline, docker, tailscale, restic, monitoring
    tests/acceptance.sh   the checks that produce evidence
    scripts/rebuild.sh    destroy, rebuild, converge, prove, collect evidence
    evidence/             output from the last run

## Quick start

    cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # fill in token, ssh key, tailscale key
    cd tofu && tofu init && tofu apply
    cd ../ansible && ansible-playbook -i inventory/hosts.yml site.yml
    ./tests/acceptance.sh

Or do the whole thing, including the destroy and the idempotence run:

    ./scripts/rebuild.sh

## Why the split is where it is

OpenTofu owns whatever the provider API owns: the server, the volume, the cloud firewall, the SSH key, DNS if you add it. State lives in a remote backend, because state on one laptop means nobody else can destroy cleanly.

cloud-init owns first boot and nothing else. It runs once and it is not idempotent, so it only creates the deploy user, installs its key, sets the hostname, makes sure python3 is present, and turns off password authentication so there is no soft window while Ansible gets going.

Ansible owns everything that has to stay true over time. Run it twice and the second run changes nothing, which is one of the things `tests/acceptance.sh` checks rather than assumes.

## The lockout problem

Closing public SSH before the tailnet is up is how people end up with a server they cannot reach. So `baseline_allow_public_ssh` starts as `true`, the Tailscale role verifies the node is actually online, and only then does the firewall drop port 22 on the public interface. The provider console stays the documented way back in if something goes wrong.

## Backups

A backup nobody has restored is a file taking up space. `restic-restore-test.sh` restores the latest snapshot into a scratch directory, compares a canary file by checksum, and writes the timing into evidence. That is the deliverable, not the fact that a backup job exists.

## Acceptance

See ACCEPTANCE.md. Twelve conditions, each mapped to the check that proves it and the evidence file it writes.
