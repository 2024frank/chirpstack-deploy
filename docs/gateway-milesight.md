# Milesight ND67 / UG67 gateway configuration

The ND67 is the same board as the UG67 (per its FCC filing). Everything here
applies to both, and mostly to the UG65/UG56 as well.

## Identifiers, from the label

- **Gateway EUI** = the base MAC with `FFFE` inserted in the middle.
  MAC `24:E1:24:AB:CD:EF` → EUI `24E124FFFEABCDEF`. The label prints both; use
  the EUI line verbatim. Transposing `FFFE` to `FFEF` is an easy typo and the
  failure is silent: the gateway connects, ChirpStack ignores it.
- OUI `24:E1:24` = Xiamen Milesight IoT.
- Factory access: Wi-Fi AP `Gateway_XXXXXX` / `iotpassword`, web UI at
  `192.168.1.1`, login `admin` / `password`. **Change all of these.**

## Getting into the web UI

In order of likelihood that it works:

1. **Wi-Fi AP** (`Gateway_XXXXXX`, browse `https://192.168.1.1`). Only exists if
   the Wi-Fi is still in AP mode. If someone configured Wi-Fi as a *client* for
   backhaul, the AP is gone: client mode replaces AP mode.
2. **Ethernet**, PC set to static `192.168.23.200/24`, browse `192.168.23.150`.
   Firmware caveat: Milesight documents this static fallback as valid only for
   firmware **< 60.0.0.46**. On newer firmware the ETH port may be a DHCP
   client. Recovery: run a DHCP server on your laptop's Ethernet interface
   (macOS: Internet Sharing), then find the gateway's lease with
   `arp -a | grep 24:e1:24`.
3. **Its current LAN/WAN IP**, if you or your network admin know it. Note the
   web UI may be disabled on the WAN-facing interface by default.
4. **Factory reset**, the last resort: hold the reset button (under the clear
   cover) >5 s while the SYS LED is solid green. Restores the AP and
   `192.168.1.1`, erases all configuration.

Login lockout: 5 wrong attempts locks the page for 10 minutes. Don't guess.

## Pointing it at ChirpStack (the built-in MQTT forwarder)

Requires firmware ≥ 60.0.0.43. `Packet Forwarder → General`:

1. In the Multi-Destination table, **disable the `Embedded NS` row**. The
   gateway ships with its own LoRaWAN network server enabled. Left on, it
   terminates device joins locally and your ChirpStack never sees the device —
   with no error anywhere. This is the single most common failure.
2. Add a destination: Type **ChirpStack-V4**, Server Address = your server,
   Port = `1883` (or `443` if 1883 is blocked — see troubleshooting), region ID
   matching the radio. Leave credentials/TLS empty until you harden.
3. **Save & Apply.** Settings do not take effect without it.
4. The row's **Connect Status** should show Connected within ~30 s.

Do not trust the Embedded NS row's "Connected" status: that row connects to
`localhost` — the gateway itself — and is always Connected. It says nothing
about your server.

## The sub-band trap

ChirpStack names US915 sub-bands 0-indexed; vendors (Milesight included) label
them 1-indexed:

| Vendor UI | Channels | MHz | ChirpStack region |
|---|---|---|---|
| Sub-band 1 | 0–7 + 64 | 902.3–903.7 | `us915_0` |
| Sub-band 2 | 8–15 + 65 | 903.9–905.3 | `us915_1` |
| … | … | … | … |
| Sub-band 8 | 56–63 + 71 | 913.5–914.9 | `us915_7` |

Milesight's US915 factory default is **Sub-band 2**, i.e. `us915_1`.

Get this wrong and everything *looks* healthy: gateway Connected, ChirpStack
shows it online, and no device ever joins. Nothing logs why. This repo's
`chirpstack.toml` enables all eight sub-bands so the server side can't be the
mismatched half.

## Milesight sensor defaults

- Join: OTAA, LoRaWAN 1.0.3, fPort 85
- **AppKey = DevEUI written twice** (e.g. DevEUI `24E124746F452258` → AppKey
  `24E124746F45225824E124746F452258`), unless random keys were ordered
- Configuration: ToolBox app over NFC, or ToolBox desktop over the Type-C port
- A sensor showing **De-activated** in ToolBox has its LoRaWAN radio off and
  will never join, no matter how correct everything else is. Activate it there.

## LEDs and power

| LED | Meaning |
|---|---|
| SYS solid green | system healthy |
| SYS red | fault |
| LoRa green | packet forwarder running |
| LoRa off | packet forwarder off |

Power: PoE 802.3af, or 6–12 V DC on the M12 connector (red = +12 V,
black = GND, yellow/white reserved), or solar.
