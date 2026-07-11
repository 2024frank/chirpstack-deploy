# chirpstack-deploy

A private LoRaWAN network with ChirpStack v4, Docker, and a Milesight ND67/UG67
gateway. This is the guide that documents the failure modes: every step here was
run against real hardware, and the traps in `docs/troubleshooting.md` are things
that actually happened, with the symptoms they produced.

```
sensors ──LoRa radio──▶ gateway ──outbound MQTT──▶ server
                                                    ├─ Mosquitto (MQTT broker)
                                                    ├─ ChirpStack v4 + Postgres + Redis
                                                    └─ your application (JSON over MQTT)
```

Two deployment targets, same stack:

| Target | Guide | Good for |
|---|---|---|
| AWS EC2 (~$17/mo) | [docs/aws.md](docs/aws.md) | gateways behind restrictive networks (campus, corporate): they only need outbound internet |
| Local machine / NUC | [docs/local.md](docs/local.md) | bench testing, LAN-only deployments |

## Quickstart (AWS)

```bash
# needs: aws cli authenticated (aws sts get-caller-identity)
./aws/provision.sh
# prints the server IP, the SSH command, and the exact gateway settings
```

## Quickstart (local)

```bash
docker compose up -d
open http://localhost:8080     # admin / admin — change it
```

## Then

1. Configure the gateway: [docs/gateway-milesight.md](docs/gateway-milesight.md).
   The two rules that matter: **disable the Embedded NS**, and know that the
   vendor's "Sub-band 2" is ChirpStack's `us915_1`.
2. Register devices headlessly: `CS_HOST=<server-ip> python3 scripts/register-device.py <devEUI> "<name>"`.
   Milesight sensors ship with AppKey = DevEUI repeated twice; the script assumes
   this unless you pass `--appkey`.
3. Watch data arrive: `./scripts/watch-mqtt.sh app` prints every uplink as JSON.

## What is deliberately different from upstream chirpstack-docker

- All eight `us915_0..7` sub-bands enabled, so a gateway is accepted whichever
  sub-band its radio uses (defuses the off-by-one naming trap).
- No `chirpstack-gateway-bridge` containers. Milesight UG6x gateways
  (firmware ≥ 60.0.0.43) carry a built-in ChirpStack MQTT Forwarder and publish
  to the broker directly. Semtech-UDP gateways are covered in
  [docs/gateway-other.md](docs/gateway-other.md).
- The broker also listens on **port 443** (mapped to MQTT). Campus and corporate
  networks that silently drop outbound 1883 essentially never drop 443. If a
  gateway shows Disconnected on 1883, change one field and you're through.

## Security

The upstream example, and therefore this quickstart, is insecure by default:
anonymous MQTT, `admin/admin`, plain HTTP. Fine on a bench, not fine on the
internet. [docs/security.md](docs/security.md) is the ordered checklist; do it
before real data flows.

## Repo layout

```
docker-compose.yml        # the stack (US915, no gateway-bridge, 443 mapped)
configuration/            # chirpstack + mosquitto configs
scripts/register-device.py  # headless device registration via the API
scripts/watch-mqtt.sh     # watch either MQTT hop live
aws/provision.sh          # one-command EC2 deployment
aws/user-data.sh          # first-boot bootstrap for the server
docs/                     # gateway config, troubleshooting, security, targets
```

MIT license. Built at Oberlin College for the Community Hub / Environmental
Dashboard LoRaWAN project.
