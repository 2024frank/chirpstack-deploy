# Deploying on a local machine (NUC, mini-PC, laptop)

Right choice when gateway and server share a LAN and you control the network.
Wrong choice when the gateway is on a network you don't control (campus,
corporate): client isolation and inter-VLAN filtering will eat the connection,
and you can't firewall-rule your way out from the client side. Verified the
hard way; see troubleshooting.md, "locked-down network".

## Linux (recommended)

```bash
git clone <this repo> && cd chirpstack-deploy
docker compose up -d
```

Give the machine a static IP or DHCP reservation — the gateway config points at
it by address. That's the whole install.

## Windows + Docker Desktop (works, with caveats)

If the machine must run Windows, know what you're signing up for:

- **Docker Desktop starts at login, not at boot.** Unattended machine =
  enable auto-login (netplwiz) or run Docker Engine inside WSL2 as a service.
- **Windows Update reboots on its own schedule.** Set active hours, defer
  updates, and make containers `restart: unless-stopped` (they are, in this
  compose file) so the stack returns after a reboot plus login.
- **Power settings:** disable sleep/hibernate; enable "power on after outage"
  in BIOS.
- **WSL2 networking:** Docker Desktop forwards published ports (1883, 8080,
  443) from the Windows side; test from another machine on the LAN, not just
  localhost.

Honestly: a $200 used mini-PC running Ubuntu Server removes this entire
section.

## Verify

```bash
./scripts/watch-mqtt.sh            # both hops; gateway hop prints protobuf noise, that's correct
CS_HOST=localhost python3 scripts/register-device.py <devEUI> "bench sensor"
```
