# HHRCS — Hunter House Remote Camera System

Unattended outdoor wildlife cinema rig at Prospect Lake, Saanich, BC.

## Components

**iOS App** (`HHRCS.xcodeproj`)
SwiftUI app for remote monitoring and control. Bundle ID: com.brandonpoole.hhrcs. Targets iOS 17 / macOS 14.

**Pi Backend** (`pi/`)
Flask REST API running on Raspberry Pi 4. Manages wildlife detection (MegaDetectorLite ONNX), BMPCC 6K Pro control via ethernet REST API, deployment lifecycle, and a two-tier agent (Tier 1 rule-based + Tier 2 Claude Haiku).

## Architecture

Pi Camera Module 3 → MegaDetectorLite ONNX → State Machine → Pi ethernet → BMPCC 6K Pro REST API

iOS App ↔ Flask API (:5001) ↔ BMPCC 6K Pro (192.168.10.2)

## Network

Pi eth0: 192.168.10.1/24 (static, NetworkManager con-name "camlink")
BMPCC eth: 192.168.10.2/24 (static, via USB-C ethernet adapter)
REST API base: http://192.168.10.2/control/api/v1

LAN: raspberrypi.local:5001
Tailscale: hhrcs-pi:5001

## Pi Service

Main: `hhrcs.service` (port 5001)

## One-time camera setup

Enable Web Media Manager on the BMPCC via Blackmagic Camera Setup (connects over USB to the camera, not the Pi). This enables the REST API and static IP assignment.
