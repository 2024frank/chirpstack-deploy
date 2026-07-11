#!/usr/bin/env python3
"""
Register a LoRaWAN device in ChirpStack v4, headlessly.

    CS_HOST=<server> python3 register-device.py <devEUI> "<name>" [--appkey HEX32]

Defaults tuned for Milesight sensors: OTAA, LoRaWAN 1.0.3, US915, and
AppKey = DevEUI repeated twice (Milesight's factory default) unless --appkey
is given. Creates the application and device profile on first use; safe to
re-run (existing objects are reused, keys are updated in place).

Auth: logs in as admin via gRPC-web on :8080 (there is no REST login
endpoint), then drives the JSON REST API on :8090.
Set CS_USER / CS_PASS to override admin/admin.
"""
import json, base64, struct, sys, os, urllib.request, urllib.error

HOST = os.environ.get("CS_HOST", "localhost")
USER = os.environ.get("CS_USER", "admin")
PASS = os.environ.get("CS_PASS", "admin")
GRPC = f"http://{HOST}:8080"
REST = f"http://{HOST}:8090"
APP_NAME = os.environ.get("CS_APP", "lorawan-devices")
DP_NAME  = os.environ.get("CS_PROFILE", "Milesight (US915, 1.0.3, OTAA)")

def pb_string_field(num, s):
    b = s.encode()
    return bytes([num << 3 | 2, len(b)]) + b

def grpc_web_login(email, password):
    msg = pb_string_field(1, email) + pb_string_field(2, password)
    frame = b"\x00" + struct.pack(">I", len(msg)) + msg
    req = urllib.request.Request(
        f"{GRPC}/api.InternalService/Login", data=base64.b64encode(frame),
        headers={"Content-Type": "application/grpc-web-text",
                 "Accept": "application/grpc-web-text", "x-grpc-web": "1"})
    raw = base64.b64decode(urllib.request.urlopen(req, timeout=10).read())
    def varint(b, i):
        shift = res = 0
        while True:
            byte = b[i]; i += 1
            res |= (byte & 0x7f) << shift
            if not byte & 0x80: return res, i
            shift += 7
    i = 0
    while i < len(raw):
        flag = raw[i]; ln = struct.unpack(">I", raw[i+1:i+5])[0]
        payload = raw[i+5:i+5+ln]; i += 5+ln
        if flag == 0x00 and payload[:1] == b"\x0a":   # field 1, length-delimited
            length, j = varint(payload, 1)            # length is a varint
            return payload[j:j+length].decode()
    raise SystemExit("login failed: no jwt in gRPC-web response")

def rest(method, path, jwt, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(REST+path, data=data, method=method,
        headers={"Authorization": "Bearer "+jwt, "Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req, timeout=10).read()
        return json.loads(r) if r else {}
    except urllib.error.HTTPError as e:
        return {"__error__": e.code, "body": e.read().decode()}

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 1:
        sys.exit(__doc__)
    dev_eui = args[0].lower().replace(":", "").replace("-", "")
    if len(dev_eui) != 16 or any(c not in "0123456789abcdef" for c in dev_eui):
        sys.exit(f"'{args[0]}' is not a 16-hex-char DevEUI")
    name = args[1] if len(args) > 1 else f"device-{dev_eui[-6:]}"
    app_key = dev_eui + dev_eui                     # Milesight default
    if "--appkey" in sys.argv:
        app_key = sys.argv[sys.argv.index("--appkey")+1].lower()
        if len(app_key) != 32:
            sys.exit("--appkey must be 32 hex chars")

    jwt = grpc_web_login(USER, PASS)
    tid = rest("GET", "/api/tenants?limit=10", jwt)["result"][0]["id"]

    apps = rest("GET", f"/api/applications?limit=100&tenantId={tid}", jwt)
    aid = next((a["id"] for a in apps.get("result", []) if a["name"] == APP_NAME), None) \
        or rest("POST", "/api/applications", jwt,
                {"application": {"name": APP_NAME, "tenantId": tid}})["id"]

    dps = rest("GET", f"/api/device-profiles?limit=100&tenantId={tid}", jwt)
    did = next((p["id"] for p in dps.get("result", []) if p["name"] == DP_NAME), None) \
        or rest("POST", "/api/device-profiles", jwt, {"deviceProfile": {
            "tenantId": tid, "name": DP_NAME, "region": "US915",
            "macVersion": "LORAWAN_1_0_3", "regParamsRevision": "A",
            "supportsOtaa": True, "uplinkInterval": 3600,
            "deviceStatusReqInterval": 1, "flushQueueOnActivate": True,
            "adrAlgorithmId": "default"}})["id"]

    if "__error__" in rest("GET", f"/api/devices/{dev_eui}", jwt):
        r = rest("POST", "/api/devices", jwt, {"device": {
            "devEui": dev_eui, "name": name,
            "applicationId": aid, "deviceProfileId": did}})
        if "__error__" in r: sys.exit(f"device create failed: {r}")
        print(f"device created: {dev_eui} ({name})")
    else:
        print(f"device exists:  {dev_eui}")

    # LoRaWAN 1.0.x: the OTAA AppKey goes in the nwkKey field.
    keys = {"deviceKeys": {"devEui": dev_eui, "nwkKey": app_key, "appKey": app_key}}
    if "__error__" in rest("GET", f"/api/devices/{dev_eui}/keys", jwt):
        r = rest("POST", f"/api/devices/{dev_eui}/keys", jwt, keys)
    else:
        r = rest("PUT", f"/api/devices/{dev_eui}/keys", jwt, keys)
    if "__error__" in r: sys.exit(f"key write failed: {r}")

    check = rest("GET", f"/api/devices/{dev_eui}/keys", jwt)
    ok = check.get("deviceKeys", {}).get("nwkKey", "").lower() == app_key
    print(f"appkey stored:  {'verified' if ok else 'MISMATCH'}")
    print(f"uplink topic:   application/{aid}/device/{dev_eui}/event/up")

if __name__ == "__main__":
    main()
