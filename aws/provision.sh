#!/usr/bin/env bash
# Provision the ChirpStack server on AWS. One instance, one security group,
# one Elastic IP. Requires: aws cli configured (aws sts get-caller-identity works).
#
# Cost (us-east-2, on-demand, July 2026 rates, verify before relying on them):
#   t4g.small  ~$0.0168/hr  ≈ $12.30/mo
#   public IPv4              ≈ $3.60/mo
#   20 GB gp3 EBS            ≈ $1.60/mo
#   total                    ≈ $17-18/mo. Terminate the instance to stop billing.
#
# Everything is tagged Project=oberlin-lorawan for easy cleanup:
#   aws ec2 terminate-instances --instance-ids <id>
set -euo pipefail

REGION="${AWS_REGION:-us-east-2}"          # Ohio. Fitting.
NAME="${DEPLOY_NAME:-chirpstack-lorawan}"
TYPE="t4g.small"
KEY_NAME="$NAME-key"
KEY_FILE="$HOME/.ssh/$KEY_NAME.pem"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== identity =="
aws sts get-caller-identity --output table --region "$REGION"

echo "== my public IP (for SSH/UI lockdown) =="
MYIP="$(curl -s https://checkip.amazonaws.com)"
echo "   $MYIP"

echo "== key pair =="
if [ ! -f "$KEY_FILE" ]; then
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "   created $KEY_FILE"
else
  echo "   exists $KEY_FILE"
fi

echo "== security group =="
VPC=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
      --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 describe-security-groups --region "$REGION" \
     --filters Name=group-name,Values="$NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ "$SG" = "None" ] || [ -z "$SG" ]; then
  SG=$(aws ec2 create-security-group --region "$REGION" --group-name "$NAME" \
       --description "ChirpStack LoRaWAN server" --vpc-id "$VPC" \
       --query 'GroupId' --output text)
  # SSH + web UI: only from this machine's current public IP.
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
    --protocol tcp --port 22   --cidr "$MYIP/32"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
    --protocol tcp --port 8080 --cidr "$MYIP/32"
  # MQTT for the gateway. /24 around the campus egress IP seen from this Mac;
  # widen or narrow once the gateway's actual egress IP is known.
  NET="$(echo "$MYIP" | cut -d. -f1-3).0/24"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
    --protocol tcp --port 1883 --cidr "$NET"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
    --protocol tcp --port 443 --cidr "$NET"
  echo "   created $SG  (22,8080 from $MYIP/32; 1883+443 from $NET)"
else
  echo "   exists $SG"
fi

echo "== ubuntu 24.04 arm64 AMI =="
AMI=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' --output text)
echo "   $AMI"

echo "== instance =="
EXISTING=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ "$EXISTING" != "None" ] && [ -n "$EXISTING" ]; then
  ID="$EXISTING"; echo "   already running: $ID"
else
  ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG" \
    --user-data "file://$HERE/user-data.sh" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Project,Value=$NAME}]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "   launched $ID"
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$ID"
fi

echo "== elastic ip =="
EIP_ALLOC=$(aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Project,Values=$NAME" \
  --query 'Addresses[0].AllocationId' --output text 2>/dev/null)
if [ "$EIP_ALLOC" = "None" ] || [ -z "$EIP_ALLOC" ]; then
  EIP_ALLOC=$(aws ec2 allocate-address --region "$REGION" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Project,Value=$NAME}]" \
    --query 'AllocationId' --output text)
fi
aws ec2 associate-address --region "$REGION" --instance-id "$ID" --allocation-id "$EIP_ALLOC" >/dev/null
IP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$EIP_ALLOC" \
     --query 'Addresses[0].PublicIp' --output text)

cat <<EOF

============================================================
 ChirpStack server is provisioning at: $IP
 First boot takes ~3-4 min (Docker install + image pulls).

 SSH:    ssh -i $KEY_FILE ubuntu@$IP
 UI:     http://$IP:8080          (admin/admin -> CHANGE IT)
 MQTT:   $IP:1883                 (gateway points here)
 Logs:   ssh in, then: sudo tail -f /var/log/cloud-init-output.log

 Gateway settings (ND67 web UI -> Packet Forwarder -> Multi-Destination):
   Type:           ChirpStack-V4
   Server Address: $IP
   Port:           1883
   Region ID:      match the gateway's sub-band (likely US915 sub-band 2)
   And DISABLE the Embedded NS row.

 Stop billing: aws ec2 terminate-instances --region $REGION --instance-ids $ID
               aws ec2 release-address --region $REGION --allocation-id $EIP_ALLOC
============================================================
EOF
