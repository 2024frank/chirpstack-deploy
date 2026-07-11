# Security checklist

The quickstart is insecure by design so that first-packet debugging is easy.
Work through this list before real data flows, top to bottom.

## 1. Change every factory credential

- ChirpStack UI `admin/admin` → UI, top-right menu, change password
- Gateway web UI `admin/password` → gateway System settings
- Gateway Wi-Fi AP `iotpassword`, if AP mode is in use

These are printed on device labels and in every manual; they are not secrets.

## 2. MQTT authentication

The example Mosquitto allows anonymous read/write on every topic. Anyone who
can reach the port can publish forged uplinks into your dataset or subscribe to
all of it. If your data feeds anything that matters (billing, compliance,
public reporting), this is the highest-value fix:

```bash
# on the server
docker compose exec mosquitto mosquitto_passwd -c -b /mosquitto/config/passwd gateway <strong-password>
docker compose exec mosquitto mosquitto_passwd -b /mosquitto/config/passwd chirpstack <strong-password>
```

In `configuration/mosquitto/config/mosquitto.conf`:

```
allow_anonymous false
password_file /mosquitto/config/passwd
```

Then set the matching username/password in `configuration/chirpstack/
region_us915_*.toml` (`[regions.gateway.backend.mqtt]`) and
`chirpstack.toml` (`[integration.mqtt]`), in the gateway's ChirpStack-V4
destination, and restart the stack.

## 3. TLS

- MQTT: real certificate (Let's Encrypt needs a DNS name) on 8883; Milesight
  gateways accept CA/client-cert config in the destination settings.
- UI: put Caddy or nginx in front of 8080 for HTTPS; stop publishing 8080
  directly.
- Until then, the security-group IP restrictions are the compensating control.

## 4. Firewall hygiene (cloud)

- Tighten 1883/443 to the gateway's egress IP once known (see aws.md).
- Keep 22/8080/8090 pinned to your own IP.
- The REST API container runs with `--insecure` (plain HTTP internally);
  don't publish 8090 wider than your own IP.

## 5. Rotate anything that leaked during setup

Screenshots and chat logs from a bring-up session commonly contain: gateway
admin passwords, AWS access keys, broker credentials. Assume anything that
appeared on a screen is burned and rotate it. Delete root AWS access keys
entirely; use an IAM user or IAM Identity Center.

## 6. Physical/RF notes

- LoRaWAN payloads are AES-encrypted end-to-end with the AppKey; the radio leg
  is not the weak point. Key handling is: Milesight default AppKeys are
  *derivable from the DevEUI printed on the device*, so anyone who photographs
  a label can register-race or impersonate that sensor on a server that still
  accepts defaults. For deployments beyond a pilot, order random keys or
  rotate AppKeys at commissioning.
- The gateway's Ethernet fallback IP (192.168.23.150) plus default password
  equals full gateway takeover for anyone with physical port access. Change
  the password (step 1) and consider disabling unused access services in the
  gateway's System → Access Service settings.
