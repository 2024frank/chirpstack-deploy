#!/bin/bash
# Cloud-init for the ChirpStack server (Ubuntu 24.04 arm64).
# Runs once at first boot as root. Log: /var/log/cloud-init-output.log
set -euxo pipefail

# --- Docker ---
apt-get update
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# --- ChirpStack stack ---
cd /opt
git clone --depth 1 https://github.com/chirpstack/chirpstack-docker.git chirpstack
cd chirpstack

# Enable all eight US915 sub-bands so the gateway is accepted whichever one
# its radio is on (Milesight "Sub-band N" is ChirpStack "us915_{N-1}").
python3 - <<'PY'
import re
p = "configuration/chirpstack/chirpstack.toml"
s = open(p).read()
regions = "".join(f'    "us915_{i}",\n' for i in range(8))
s = re.sub(r"enabled_regions=\[.*?\]", "enabled_regions=[\n" + regions + "  ]", s, flags=re.S)
open(p, "w").write(s)
PY

# Also serve MQTT on 443: campus/corporate networks that silently drop
# outbound 1883 essentially never drop 443.
python3 - <<'PY'
s = open("docker-compose.yml").read()
if "443:1883" not in s:
    s = s.replace('- "1883:1883"', '- "1883:1883"\n      - "443:1883"')
    s = s.replace("- 1883:1883", "- 1883:1883\n      - 443:1883") if '"1883:1883"' not in s else s
    open("docker-compose.yml", "w").write(s)
PY

# Start only what the Milesight MQTT-forwarder path needs.
# No gateway-bridge containers: the ND67/UG67 publishes MQTT directly.
docker compose up -d chirpstack chirpstack-rest-api postgres redis mosquitto

# --- convenience for later SSH sessions ---
usermod -aG docker ubuntu
echo "cd /opt/chirpstack" >> /home/ubuntu/.bashrc

echo "CHIRPSTACK BOOTSTRAP DONE"
