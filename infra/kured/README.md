# kured

Handles weekly node drain → pre-reboot cleanup → reboot → uncordon automatically, one node at a time.

## How it works

1. kured watches for `/var/run/reboot-required` on each node every hour
2. On Tuesday between 06:00 and 08:00 UTC, kured acquires a cluster-wide lock and processes one node at a time
3. kured cordons and drains the node, then calls `/usr/local/bin/pre-reboot.sh` (deployed by bootstrap)
4. The pre-reboot script: prunes container images, runs `apt upgrade`, cleans logs/tmp/firmware backups, then reboots
5. kured uncordons the node after it comes back

Pre-reboot logs are written to `/var/log/kured/pre-reboot-<date>.log` on each node.

## Prerequisites

Bootstrap must have run on all nodes (deploys `/usr/local/bin/pre-reboot.sh`).

The sealed `kube-system/kured-telegram` secret holds the Telegram target (`url`, in Shoutrrr form
`telegram://<bot token>@telegram?chats=<chat id>`); change it with `scripts/secrets.sh set <cluster> kube-system/kured-telegram url=`.

## Notes

Only enable after all nodes are bootstrapped and the cluster is healthy.
