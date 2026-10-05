# VPS deploy hardening

Server-side half of `.github/workflows/deploy.yml`. Install as root:

| File | Install to | Mode |
|---|---|---|
| `engineerfamily-deploy` | `/usr/local/sbin/` | `root:root 755` |
| `engineerfamily-deploy-wrapper` | `/usr/local/sbin/` | `root:root 755` |
| `sudoers-80-deploy` | `/etc/sudoers.d/80-deploy` | `root:root 440` (check with `visudo -cf`) |
| `sshd-00-hardening.conf` | `/etc/ssh/sshd_config.d/00-hardening.conf` | check with `sshd -t` |

The `deploy` account is not in the `docker` group and has no other sudo rights. Its
`~/.ssh/authorized_keys` is root-owned and holds the CI public key prefixed with `restrict `.
Over SSH it needs key + password and can run only `deploy prod|preprod` or `status prod|preprod`.

GitHub secrets: `VPS_HOST`, `VPS_SSH_KEY` (private key), `VPS_SSH_PASSWORD`,
`VPS_KNOWN_HOSTS` (the server's `ssh_host_ed25519_key.pub` line, prefixed with the host IP).
