#include "SerialSecurityHandler.h"

SerialSecurityHandler::SerialSecurityHandler(BMDCameraConnection* bmdCameraConnectionPtr)
{
  _bmdCameraConnectionPtr = bmdCameraConnectionPtr;
}

// Called from the BLE event task while loop() is blocked inside bleClient->connect().
// We must read serial directly here — loop() cannot run at this point.
uint32_t SerialSecurityHandler::onPassKeyRequest()
{
    _bmdCameraConnectionPtr->status = BMDCameraConnection::NeedPassKey;
    Serial.println("[BLE] state=NeedPassKey");

    String buf = "";
    unsigned long start = millis();

    while (millis() - start < 60000UL) {
        while (!Serial.available())
            vTaskDelay(1);

        char ch = (char)Serial.read();

        if (ch == '(') {
            buf = "(";
        } else if (ch == ')') {
            buf += ')';
            // Expect (PASSKEY:XXXXXX)
            if (buf.startsWith("(PASSKEY:") && buf.length() == 16) {
                String digits = buf.substring(9, 15);
                uint32_t code = (uint32_t)digits.toInt();
                if (code >= 100000 && code <= 999999) {
                    Serial.println("[BLE] passkey accepted: " + digits);
                    return code;
                }
            }
            buf = "";
        } else if (buf.length() > 0) {
            buf += ch;
        }
    }

    Serial.println("[BLE] passkey timeout");
    return 0;
}

void SerialSecurityHandler::onPassKeyNotify(uint32_t pass_key) {}

bool SerialSecurityHandler::onConfirmPIN(uint32_t pin)
{
    return true;
}

bool SerialSecurityHandler::onSecurityRequest()
{
    return true;
}

void SerialSecurityHandler::onAuthenticationComplete(esp_ble_auth_cmpl_t auth_cmpl)
{
    if(auth_cmpl.success)
        _bmdCameraConnectionPtr->status = BMDCameraConnection::Connected;
    else
        _bmdCameraConnectionPtr->status = BMDCameraConnection::FailedPassKey;
}