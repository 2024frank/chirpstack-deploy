# Troubleshooting

Every entry here was hit on real hardware. Ordered by how often it happens.

## Gateway says "online" but ChirpStack says never seen

**First, establish ground truth on the server:**

```bash
docker compose logs mosquitto | grep -vE "172\.|::1" | grep -i "new client"
```

If no external IP has ever connected, the gateway is not reaching you, whatever
its UI says. Causes, in order:

1. **You're reading the Embedded NS row.** Its Connect Status is always
   "Connected" — it connects to localhost, i.e. itself. Check the row with
   *your server's address* in it.
2. **Save & Apply was never clicked.** Milesight settings don't apply on field
   edit.
3. **Outbound port 1883 is blocked** (campus/corporate networks do this
   silently). Test from the gateway itself: Maintenance → Tools → Ping your
   server. Ping works but MQTT doesn't = port block. Fix: this stack maps
   broker port **443** as well; change the Port field to 443. Networks that
   block outbound 443 don't exist in practice.
4. **Gateway EUI typo** in ChirpStack. The EUI is MAC + `FFFE` in the middle;
   `FFEF` transpositions look right and fail silently.

## Gateway connected, devices never join

1. **Embedded NS still enabled** on the gateway. It answers the join locally
   and eats it. Disable it: Packet Forwarder → General → Multi-Destination.
2. **Sub-band mismatch.** Vendor "Sub-band 2" = ChirpStack `us915_1` (their UI
   is 1-indexed, ChirpStack is 0-indexed). With this repo's config all eight
   are enabled server-side, so if you still see nothing, the *device* and
   *gateway* radios disagree — check the sensor's region/sub-band in ToolBox.
3. **Sensor is de-activated.** Milesight sensors can ship with LoRaWAN off.
   ToolBox (NFC) → status "De-activated" → activate.
4. **Wrong AppKey.** Milesight default is DevEUI twice. In ChirpStack v4 with
   LoRaWAN 1.0.x, the key goes in the **nwkKey** field of the device-keys API
   (the UI labels it Application key — the REST field name differs).
5. **Frame-counter reset rejection** after re-flashing or factory-resetting a
   device: either enable "skip fcnt check" temporarily or delete and re-create
   the device activation.

## MQTT payloads look like binary garbage

Both hops share the broker but not the encoding:

| Topic | Direction | Payload |
|---|---|---|
| `{region}/gateway/{eui}/event/…` | gateway → ChirpStack | **protobuf** |
| `application/{app-id}/device/{devEUI}/event/…` | ChirpStack → you | **JSON** (`[integration.mqtt] json=true`) |

Your application subscribes to the second one. If you see binary there, someone
set `json=false`.

## Web UI of the gateway unreachable at 192.168.1.1

The AP (and its 192.168.1.1) only exists in AP mode. Wi-Fi client mode removes
it. See gateway-milesight.md, "Getting into the web UI", for the ETH fallback
and its firmware caveat.

## Diagnosing "can I even reach it" on a locked-down network

`traceroute -n <ip>` from your laptop. If packets die at the second or third
hop (a router you don't own), the network is filtering between segments —
that's a conversation with IT, not a config fix. Corollary: prefer
architectures where the *gateway dials out* (MQTT to a cloud server) over ones
where anything must dial *in* to the gateway's network.

## ChirpStack API: creating a gateway fails with "downlink_priority must be > 0"

The REST API requires `downlinkPriority ≥ 1` on gateway create even though the
field is undocumented as required. Set it to 1.

## ChirpStack REST vs gRPC ports

- `:8080` serves the web UI **and gRPC-web** (login lives here:
  `POST /api.InternalService/Login`, protobuf over grpc-web-text)
- `:8090` is the JSON REST API (`chirpstack-rest-api` container), but it has
  **no login endpoint** — get a JWT from 8080 or create an API key in the UI

`scripts/register-device.py` handles this dance for you.

## Broker restarted, is ChirpStack broken now?

No. ChirpStack's MQTT client reconnects automatically; you'll see a burst of
internal reconnections in the mosquitto log. Devices and gateways are
unaffected (state lives in Postgres/Redis, not the broker).

## Losing Redis

Redis holds device *sessions*. Losing it means every OTAA device must rejoin
(which happens automatically on its next join attempt, but Class-A sensors that
only uplink may take a while to notice). Back up accordingly; see security.md.
