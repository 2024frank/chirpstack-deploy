# Deploying on AWS

One EC2 instance runs the whole stack. The gateway only makes *outbound*
connections to it, which is why this works from behind campus/corporate
firewalls that you could never get an inbound rule through.

## Cost (us-east-2, on-demand, mid-2026 — verify current prices)

| Item | ~Monthly |
|---|---|
| t4g.small (2 vCPU / 2 GB, arm64) | $12.30 |
| Public IPv4 | $3.60 |
| 20 GB gp3 EBS | $1.60 |
| **Total** | **≈ $17–18** |

Terminate the instance and release the Elastic IP to stop all charges.

## Deploy

```bash
aws sts get-caller-identity        # confirm you're authenticated
./aws/provision.sh
```

The script is idempotent: it creates (or reuses) a key pair, a security group,
a t4g.small running Ubuntu 24.04 arm64 with `aws/user-data.sh` as first-boot
bootstrap, and an Elastic IP. It ends by printing the server address, the SSH
command, and the exact values to type into the gateway.

First boot takes 3–5 minutes (Docker install + image pulls). Watch it:

```bash
ssh -i ~/.ssh/<name>-key.pem ubuntu@<ip> sudo tail -f /var/log/cloud-init-output.log
```

## Security group model

| Port | Open to | Why |
|---|---|---|
| 22, 8080, 8090 | your IP/32 at provision time | SSH, UI, REST API |
| 1883, 443 | wide during bring-up | the gateway's egress IP is usually unknown until it connects |

**After the gateway connects**, read its source IP from the mosquitto log and
tighten:

```bash
ssh in, then: docker compose logs mosquitto | grep -i "new client" | grep -vE "172\.|::1"
aws ec2 revoke-security-group-ingress  --group-id <sg> --protocol tcp --port 1883 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id <sg> --protocol tcp --port 1883 --cidr <gateway-egress-ip>/32
# repeat for 443
```

If your own IP changes (home DHCP, moving networks), re-authorize 22/8080/8090
for the new address the same way.

## Why port 443 is mapped to MQTT

Some networks silently drop outbound 1883. Nothing drops outbound 443. The
compose file maps host 443 → broker 1883 so a blocked gateway needs a one-field
change (Port: 443), not a network exception request. If you later put HTTPS on
this box, move MQTT-over-443 to a second IP or use MQTT-over-TLS on 8883
instead.

## Backups

- PostgreSQL is the source of truth (devices, keys, gateways, tenants):
  `docker compose exec -T postgres pg_dump -U chirpstack chirpstack > backup.sql`
- Redis holds device sessions; losing it forces rejoins but loses no data.
- Or snapshot the whole EBS volume from the console/CLI.

## Teardown

```bash
aws ec2 terminate-instances --instance-ids <id>
aws ec2 release-address --allocation-id <eipalloc>
aws ec2 delete-security-group --group-id <sg>
aws ec2 delete-key-pair --key-name <name>-key
```
