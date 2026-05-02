# HHRCS — Hunter House Remote Camera System

Unattended outdoor wildlife cinema rig at Prospect Lake, Saanich, BC.

## Components

**iOS App** (`HHRCS.xcodeproj`)
SwiftUI app for remote monitoring and control. Bundle ID: com.brandonpoole.hhrcs. Targets iOS 17 / macOS 14.

**Pi Backend** (`pi/`)
Flask REST API running on Raspberry Pi 4. Manages wildlife detection (MegaDetectorLite ONNX), BMPCC 6K Pro control via ESP32 BLE bridge, deployment lifecycle, and a two-tier agent (Tier 1 rule-based + Tier 2 Claude Haiku).

**ESP32 Firmware** (`esp32/`)
PlatformIO project (env `hhrcs-bridge`). Patches Magic-Pocket-Control-ESP32 for serial passkey injection. Board: ELEGOO ESP32 (CP2102). Build: `cd esp32 && pio run -e hhrcs-bridge`.

## Architecture

Pi Camera Module 3 → MegaDetectorLite ONNX → State Machine → ESP32 (USB serial) → BLE → BMPCC 6K Pro

iOS App ↔ Flask API (:5001) ↔ ESP32 Bridge (:5002)

## Pi Service

Main: `hhrcs.service` (port 5001)
ESP32 bridge: `esp32-bridge.service` (port 5002)

## Network

LAN: raspberrypi.local:5001
Tailscale: hhrcs-pi:5001
