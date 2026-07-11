# Non-Milesight gateways (Semtech UDP / Basics Station)

This stack omits the `chirpstack-gateway-bridge` containers because Milesight
UG6x gateways bridge to MQTT themselves. For gateways that only speak Semtech
UDP or Basics Station, add the bridge back to `docker-compose.yml`:

```yaml
  chirpstack-gateway-bridge:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    ports:
      - "1700:1700/udp"
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    environment:
      - INTEGRATION__MQTT__EVENT_TOPIC_TEMPLATE=us915_1/gateway/{{ .GatewayID }}/event/{{ .EventType }}
      - INTEGRATION__MQTT__STATE_TOPIC_TEMPLATE=us915_1/gateway/{{ .GatewayID }}/state/{{ .StateType }}
      - INTEGRATION__MQTT__COMMAND_TOPIC_TEMPLATE=us915_1/gateway/{{ .GatewayID }}/command/#
    depends_on:
      - mosquitto
```

Set the topic prefix (`us915_1` above) to the sub-band the gateway radio
actually uses. Unlike the server's `enabled_regions`, this one cannot be
"all of them" — the bridge stamps one prefix on everything it forwards.

For Basics Station, use the `chirpstack-gateway-bridge-basicstation` variant on
port 3001 with the matching `-us915_N.toml` config from `configuration/`.

Security note: Semtech UDP has **no authentication of any kind**. Any host
that can reach port 1700 can claim any Gateway EUI and inject fabricated
uplinks. Never expose 1700 to the internet; restrict it to known gateway
egress IPs, or prefer Basics Station (TLS + per-gateway credentials) for
anything outside a trusted LAN.
