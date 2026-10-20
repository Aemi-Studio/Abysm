"""Choose exactly the requested iOS runtime; never silently substitute the floor."""
import json
import os
import subprocess

def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True)

requested = os.environ["REQUESTED_RUNTIME"]
runtimes = [
    runtime for runtime in json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
    if runtime.get("isAvailable") and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
    and (requested == "latest" or runtime["version"] == requested)
]
if not runtimes:
    raise SystemExit(f"Required iOS runtime unavailable: {requested}")
runtime = max(runtimes, key=lambda item: (
    tuple(map(int, item["version"].split("."))), len(item.get("supportedDeviceTypes", []))
))
phones = [device for device in runtime.get("supportedDeviceTypes", []) if device.get("productFamily") == "iPhone"]
if not phones:
    raise SystemExit(f"No compatible iPhone device type in {runtime['identifier']}")
device_type = next((device for device in phones if device["name"] == "iPhone 16 Pro"), phones[0])
device = simctl("create", "Abysm-CI", device_type["identifier"], runtime["identifier"]).strip()
with open(os.environ["GITHUB_ENV"], "a") as environment:
    environment.write(f"SIMULATOR_ID={device}\n")
print(f"Selected {runtime['name']} ({runtime['version']}), device {device}")
