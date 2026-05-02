#include <Arduino.h>

// Must be defined before any library headers that check these macros
#define USING_TFT_ESPI 0
#define USING_M5GFX 0
#define USING_M5_BUTTONS 0

#include "Camera/ConstantsTypes.h"
#include "Camera/PacketWriter.h"
#include "CCU/CCUUtility.h"
#include "CCU/CCUPacketTypes.h"
#include "CCU/CCUValidationFunctions.h"
#include "Camera/BMDCameraConnection.h"
#include "Camera/BMDCamera.h"
#include "BMDControlSystem.h"

// Required library singletons
BMDCameraConnection cameraConnection;
std::shared_ptr<BMDControlSystem> BMDControlSystem::instance = nullptr;
BMDCameraConnection* BMDCameraConnection::instancePtr = &cameraConnection;

// ── Helpers ────────────────────────────────────────────────────────────────

static String statusName(BMDCameraConnection::ConnectionStatus s) {
    switch (s) {
        case BMDCameraConnection::Disconnected:           return "Disconnected";
        case BMDCameraConnection::Connected:              return "Connected";
        case BMDCameraConnection::Connecting:             return "Connecting";
        case BMDCameraConnection::Scanning:               return "Scanning";
        case BMDCameraConnection::ScanningFound:          return "ScanningFound";
        case BMDCameraConnection::ScanningNoneFound:      return "ScanningNoneFound";
        case BMDCameraConnection::NeedPassKey:            return "NeedPassKey";
        case BMDCameraConnection::FailedPassKey:          return "FailedPassKey";
        case BMDCameraConnection::IncompatibleProtocol:   return "IncompatibleProtocol";
        case BMDCameraConnection::ReceivedInitialPayload: return "ReceivedInitialPayload";
        default:                                          return "Unknown";
    }
}

static void emitStatus(BMDCameraConnection::ConnectionStatus s) {
    Serial.println("[BLE] state=" + statusName(s));
}

// ── Command handlers ───────────────────────────────────────────────────────

static void handleRecord(const String& value) {
    if (!BMDControlSystem::getInstance()->hasCamera()) return;
    auto cam = BMDControlSystem::getInstance()->getCamera();
    if (!cam->hasTransportMode()) return;

    auto info = cam->getTransportMode();
    if (value == "START") {
        info.mode = CCUPacketTypes::MediaTransportMode::Record;
    } else if (value == "STOP") {
        info.mode = CCUPacketTypes::MediaTransportMode::Preview;
    } else {
        return;
    }
    PacketWriter::writeTransportInfo(info, &cameraConnection);
}

static void handleStatus() {
    emitStatus(cameraConnection.status);
    if (cameraConnection.status == BMDCameraConnection::Connected &&
        BMDControlSystem::getInstance()->hasCamera()) {
        auto cam = BMDControlSystem::getInstance()->getCamera();
        Serial.println("[CAM] recording=" + String(cam->isRecording ? "1" : "0"));
    }
}

static void processCommand(const String& cmd) {
    if (cmd.length() < 3) return;

    // Strip outer parens
    String inner = cmd.substring(1, cmd.length() - 1);
    int colon = inner.indexOf(':');
    String name  = (colon >= 0) ? inner.substring(0, colon) : inner;
    String value = (colon >= 0) ? inner.substring(colon + 1) : "";
    name.trim();
    value.trim();

    if (name == "STATUS") {
        handleStatus();
        return;
    }

    if (name == "RESET") {
        Serial.println("[HHRCS] software reset requested");
        delay(100);
        ESP.restart();
        return;
    }

    if (cameraConnection.status != BMDCameraConnection::Connected) {
        Serial.println("[ERR] not connected, ignoring " + name);
        return;
    }

    if (name == "RECORD") {
        handleRecord(value);
    } else if (name == "ISO") {
        PacketWriter::writeISO(value.toInt(), &cameraConnection);
        Serial.println("[CAM] ISO=" + value);
    } else if (name == "SHUTTER") {
        // SHUTTER:180 → angle 180° × 100 = 18000 (library expects x100)
        PacketWriter::writeShutterAngle(value.toInt() * 100, &cameraConnection);
        Serial.println("[CAM] SHUTTER=" + value);
    } else if (name == "WB") {
        // WB:5600 or WB:5600:5 (kelvin:tint)
        int sep = value.indexOf(':');
        short wb   = (sep >= 0) ? value.substring(0, sep).toInt() : value.toInt();
        short tint = (sep >= 0) ? value.substring(sep + 1).toInt() : 0;
        PacketWriter::writeWhiteBalance(wb, tint, &cameraConnection);
        Serial.println("[CAM] WB=" + String(wb) + " TINT=" + String(tint));
    } else if (name == "AUTOWB") {
        PacketWriter::writeAutoWhiteBalance(&cameraConnection);
        Serial.println("[CAM] AUTO WB");
    } else if (name == "ND") {
        // ND ordinal: 0=CLEAR, 1=ND1/4 (2-stop), 2=ND1/16 (4-stop), 3=ND1/64 (6-stop)
        byte ndOrdinal = 0;
        if      (value == "CLEAR") ndOrdinal = 0;
        else if (value == "ND2")   ndOrdinal = 1;
        else if (value == "ND4")   ndOrdinal = 2;
        else if (value == "ND6")   ndOrdinal = 3;
        // Parameter 0x10 is past the published Video spec — bypass CCU validation
        // and send directly; camera may or may not respond depending on firmware
        std::vector<byte> ndData = { ndOrdinal };
        CCUPacketTypes::Command ndCmd(
            CCUPacketTypes::kBroadcastTarget,
            CCUPacketTypes::CommandID::ChangeConfiguration,
            CCUPacketTypes::Category::Video,
            0x10,
            CCUPacketTypes::OperationType::AssignValue,
            static_cast<byte>(CCUPacketTypes::DataTypes::kInt8),
            ndData
        );
        cameraConnection.sendCommandToOutgoing(ndCmd, true);
        Serial.println("[CAM] ND=" + value + " ordinal=" + String(ndOrdinal));
    }
}

// ── Setup ──────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println("[HHRCS] BLE bridge v2 starting");

    // Initialise BLE with SerialSecurityHandler (modified to use passKeyReady)
    cameraConnection.initialise();
    emitStatus(BMDCameraConnection::Disconnected);

    // Start scanning immediately
    cameraConnection.scan();
    emitStatus(BMDCameraConnection::Scanning);
}

// ── Loop ───────────────────────────────────────────────────────────────────

static String serialBuf = "";
static BMDCameraConnection::ConnectionStatus lastStatus = BMDCameraConnection::Disconnected;
static unsigned long lastConnectedTime = 0;
static unsigned long watchdogSince = 0;      // millis when bad-state period started
static bool watchdogTriggered = false;        // set when watchdog fires; cleared on Connected

void loop() {
    // Accumulate serial input; dispatch complete (CMD:VALUE) commands
    while (Serial.available() > 0) {
        char c = (char)Serial.read();
        if (c == '(') {
            serialBuf = "(";
        } else if (c == ')') {
            serialBuf += ')';
            processCommand(serialBuf);
            serialBuf = "";
        } else if (serialBuf.length() > 0) {
            serialBuf += c;
        }
    }

    // Detect and emit status transitions.
    // NeedPassKey is already emitted by SerialSecurityHandler directly.
    auto cur = cameraConnection.status;
    if (cur != lastStatus) {
        if (cur != BMDCameraConnection::NeedPassKey)
            emitStatus(cur);
        if (cur == BMDCameraConnection::Connected && watchdogTriggered) {
            Serial.println("[WATCHDOG] Reconnected to BMPCC");
            watchdogTriggered = false;
        }
        lastStatus = cur;
    }

    unsigned long now = millis();

    switch (cur) {
        case BMDCameraConnection::Disconnected:
            if (now - lastConnectedTime >= 5000) {
                Serial.println("[BLE] rescanning...");
                cameraConnection.scan();
                lastConnectedTime = now;
            }
            break;

        case BMDCameraConnection::ScanningFound:
            // Brief pause so the camera's BLE stack is ready to accept after advertising
            delay(1500);
            cameraConnection.connect(cameraConnection.cameraAddresses[0]);
            lastConnectedTime = now;
            break;

        case BMDCameraConnection::ScanningNoneFound:
            cameraConnection.status = BMDCameraConnection::Disconnected;
            lastConnectedTime = now;
            break;

        case BMDCameraConnection::Connected:
            lastConnectedTime = now;
            break;

        case BMDCameraConnection::FailedPassKey:
            Serial.println("[BLE] passkey failed, clearing bond and retrying");
            BMDCameraConnection::clearBondedDevices();
            cameraConnection.status = BMDCameraConnection::Disconnected;
            lastConnectedTime = 0;
            break;

        default:
            break;
    }

    // ── BLE reconnect watchdog ─────────────────────────────────────────────
    // Fire if we're stuck outside Connected/Connecting/NeedPassKey for 30s.
    bool wdBadState = (cur != BMDCameraConnection::Connected &&
                       cur != BMDCameraConnection::Connecting &&
                       cur != BMDCameraConnection::NeedPassKey);
    if (!wdBadState) {
        watchdogSince = now;   // keep resetting while in a recoverable/good state
    } else if (now - watchdogSince >= 30000UL) {
        Serial.println("[WATCHDOG] BLE not connected for 30s — attempting reconnect");
        cameraConnection.scan();
        watchdogTriggered = true;
        watchdogSince = now;   // reset for next 30s interval
    }

    delay(200);
}
