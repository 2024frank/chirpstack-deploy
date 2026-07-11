#!/usr/bin/env bash
# Watch both MQTT hops on the local ChirpStack stack.
#
#   ./watch-mqtt.sh            both hops
#   ./watch-mqtt.sh gateway    gateway -> chirpstack only (protobuf, shown as byte counts)
#   ./watch-mqtt.sh app        chirpstack -> integration layer only (JSON, shown verbatim)
#
# Gateway hop  : us915_N/gateway/{eui}/event/{up,stats,ack}          protobuf
# App hop      : application/{app}/device/{devEUI}/event/{event}     JSON
#
# Nothing will print until a gateway actually reaches mosquitto:1883.

set -euo pipefail
cd "$(dirname "$0")"

# An MQTT '+' must span exactly one topic level, so the region prefix cannot be
# written as 'us915_+'. It is its own level, matched by a bare '+'.
GW_TOPIC='+/gateway/+/event/+'
APP_TOPIC='application/+/device/+/event/+'

mode="${1:-both}"
topics=()
case "$mode" in
  gateway) topics=(-t "$GW_TOPIC") ;;
  app)     topics=(-t "$APP_TOPIC") ;;
  both)    topics=(-t "$GW_TOPIC" -t "$APP_TOPIC") ;;
  *) echo "usage: $0 [gateway|app|both]" >&2; exit 2 ;;
esac

if ! docker compose ps --status running --services 2>/dev/null | grep -qx mosquitto; then
  echo "mosquitto is not running. Start the stack first:  docker compose up -d" >&2
  exit 1
fi

echo "Watching ${mode} hop(s). Ctrl-C to stop. Silence means nothing is publishing yet."
echo

# -v prints "topic payload". Gateway payloads are protobuf, so they render as
# binary noise; that is expected and still tells you the gateway is alive.
exec docker compose exec -T mosquitto mosquitto_sub -h localhost -p 1883 "${topics[@]}" -v
