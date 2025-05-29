#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <ESP32Servo.h>
#include <SPI.h>
#include <MFRC522.h>
#include <PZEM004Tv30.h>

// WiFi credentials
const char* ssid = "FOXG";
const char* password = "55555555";

// Supabase configuration
const char* supabaseUrl = "https://fglrhaqjcsohzyqgmqei.supabase.co";
const char* supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnbHJoYXFqY3NvaHp5cWdtcWVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQxMTAxNTQsImV4cCI6MjA1OTY4NjE1NH0.NGS3fGa1qho-8JzmFNHNIhEIDnv-fu6Tk_HTvomt1es";

// Pin definitions
#define DHT_PIN 26
#define DHT_TYPE DHT11
#define SERVO_PIN 25
#define RST_PIN 21
#define SS_PIN 5
#define PZEM_RX_PIN 16
#define PZEM_TX_PIN 17
#define FAN_PIN 4
#define TOUCH_PIN1 27  // OUT1: Turn fan ON
#define TOUCH_PIN2 14  // OUT2: Turn fan OFF
#define TOUCH_PIN3 12  // OUT3: Increase speed
#define TOUCH_PIN4 13  // OUT4: Toggle relay manually
#define RELAY_PIN 33   // Relay control pin
#define LED_PIN 2      // LED for temperature warning (D2)
#define LED_SUPABASE_PIN 32 // LED controlled by Supabase (D32)
#define PIR_PIN 3      // PIR sensor pin

// Device IDs
const int VOLTAGE_DEVICE_ID = 54;
const int CURRENT_DEVICE_ID = 55;
const int HUMIDITY_DEVICE_ID = 53;
const int DOOR_DEVICE_ID = 3;     // door
const int TEMPERATURE_DEVICE_ID = 6;
const int FAN_DEVICE_ID = 2;      // fan
const int RELAY_DEVICE_ID = 4;    // power
const int MOTION_DEVICE_ID = 58;
const int LAMP_DEVICE_ID = 1;     // lamp

// Timing and state
struct SystemState {
  unsigned long lastSensorRead = 0;
  unsigned long lastDoorCheck = 0;
  unsigned long lastRFIDCheck = 0;
  unsigned long lastTouchTime = 0;
  unsigned long servoMoveTime = 0;
  unsigned long lastMotionTime = 0;
  unsigned long lastSupabaseCheck = 0;
  unsigned long lastDHTRead = 0;
  unsigned long supabaseOverrideUntil = 0; // Time until Supabase override expires
  bool servoActive = false;
  bool touch1Last = false;
  bool touch2Last = false;
  bool touch3Last = false;
  bool touch4Last = false;
  bool motionDetected = false;
  bool tempLedBlinking = false; // Track if LED D2 is blinking
  int lastPirState = LOW;
} state;

const unsigned long SENSOR_READ_INTERVAL = 30000; // Read sensors every 30s
const unsigned long DOOR_CHECK_INTERVAL = 1000;   // Check door every 1s
const unsigned long SERVO_DELAY = 8000;           // Keep door open for 8s
const unsigned long RFID_CHECK_INTERVAL = 50;     // Check RFID every 50ms
const unsigned long DEBOUNCE_INTERVAL = 200;      // Debounce interval for touch
const unsigned long MOTION_TIMEOUT = 20000;       // 20s relay ON time
const unsigned long SUPABASE_CHECK_INTERVAL = 5000; // Check Supabase every 5s
const unsigned long DHT_READ_INTERVAL = 2000;     // Read DHT every 2s
const unsigned long SUPABASE_OVERRIDE_DURATION = 5000; // 5s override for Supabase
const float TEMP_THRESHOLD = 30.0;                // Temperature threshold for LED D2
const int MAX_WIFI_RETRIES = 10;                  // Max WiFi retries

// Fan and relay state
bool fanState = false;
int fanSpeed = 0;
bool relayState = false;       // Actual relay state (PIR or manual)
bool relayManualState = false; // Manual relay state (via TOUCH_PIN4 or Supabase)
const int speedLevels[] = {0, 128, 255};  // Fan speed levels
const int maxLevel = 2;                   // Index of max speed

// Valid RFID UID
const String validUID = "9F 57 BA 1F";

// Initialize objects
DHT dht(DHT_PIN, DHT_TYPE);
Servo myServo;
MFRC522 rfid(SS_PIN, RST_PIN);
PZEM004Tv30 pzem(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);

// Connect to WiFi
bool connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.print("Đang kết nối WiFi...");
  WiFi.begin(ssid, password);
  int retryCount = 0;
  while (WiFi.status() != WL_CONNECTED && retryCount < MAX_WIFI_RETRIES) {
    delay(500);
    Serial.print(".");
    retryCount++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi đã kết nối");
    Serial.print("RSSI: "); Serial.println(WiFi.RSSI());
    return true;
  } else {
    Serial.println("Kết nối WiFi thất bại!");
    return false;
  }
}

// Update device state on Supabase (using device_name)
void updateDeviceState(String deviceName, String stateValue) {
  if (!connectWiFi()) {
    Serial.println("Không thể cập nhật Supabase: Không có WiFi");
    return;
  }

  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/devices?device_name=eq." + deviceName;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("apikey", supabaseKey);

  StaticJsonDocument<256> doc;
  doc["state"] = stateValue;
  String jsonData;
  serializeJson(doc, jsonData);

  int httpCode = http.PATCH(jsonData);
  Serial.print("HTTP PATCH ("); Serial.print(deviceName); Serial.print(") code: "); Serial.println(httpCode);
  if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED || httpCode == 204) {
    Serial.println("Trạng thái thiết bị được cập nhật thành " + stateValue);
  } else {
    Serial.println("HTTP PATCH thất bại ("); Serial.print(deviceName); Serial.println(")");
    Serial.println("Phản hồi lỗi: " + http.getString());
  }
  http.end();
  delay(100); // Ngăn chặn quá tải WiFi
}

// Update relay status on Supabase (power, id=4)
void updateRelayStatus(const char* status) {
  if (!connectWiFi()) {
    Serial.println("Không thể cập nhật Supabase (power): Không có WiFi");
    return;
  }

  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/devices?id=eq." + String(RELAY_DEVICE_ID);
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("apikey", supabaseKey);

  StaticJsonDocument<100> doc;
  doc["state"] = status;
  String payload;
  serializeJson(doc, payload);

  Serial.println("Gửi đến Supabase (power): " + payload);
  int httpCode = http.PATCH(payload);
  if (httpCode == 200 || httpCode == 204) {
    Serial.println("Supabase cập nhật (power): state = " + String(status));
  } else {
    Serial.print("Cập nhật Supabase thất bại (power), mã HTTP: ");
    Serial.println(httpCode);
    Serial.println("Phản hồi: " + http.getString());
  }
  http.end();
}

// Update lamp status on Supabase (lamp, id=1)
void updateLampStatus(const char* status) {
  if (!connectWiFi()) {
    Serial.println("Không thể cập nhật Supabase (lamp): Không có WiFi");
    return;
  }

  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/devices?id=eq." + String(LAMP_DEVICE_ID);
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("apikey", supabaseKey);

  StaticJsonDocument<100> doc;
  doc["state"] = status;
  String payload;
  serializeJson(doc, payload);

  Serial.println("Gửi đến Supabase (lamp): " + payload);
  int httpCode = http.PATCH(payload);
  if (httpCode == 200 || httpCode == 204) {
    Serial.println("Supabase cập nhật (lamp): state = " + String(status));
  } else {
    Serial.print("Cập nhật Supabase thất bại (lamp), mã HTTP: ");
    Serial.println(httpCode);
    Serial.println("Phản hồi: " + http.getString());
  }
  http.end();
}

// Log history to Supabase
void logHistory(int deviceId, String action) {
  if (!connectWiFi()) {
    Serial.println("Không thể ghi log vào lịch sử: Không có WiFi");
    return;
  }

  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/history";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("apikey", supabaseKey);

  StaticJsonDocument<256> doc;
  doc["device_id"] = deviceId;
  doc["action"] = action;
  doc["timestamp"] = "now()";
  String jsonData;
  serializeJson(doc, jsonData);

  int httpCode = http.POST(jsonData);
  Serial.print("HTTP POST (history) code: "); Serial.println(httpCode);
  if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_CREATED || httpCode == 204) {
    Serial.println("Lịch sử đã được ghi: " + action);
  } else {
    Serial.println("HTTP POST thất bại (history)");
    Serial.println("Phản hồi lỗi: " + http.getString());
  }
  http.end();
  delay(100); // Ngăn chặn quá tải WiFi
}

// Read device status from Supabase
String readDeviceStatus(int deviceId) {
  if (!connectWiFi()) {
    Serial.println("Không thể đọc Supabase: Không có WiFi");
    return "";
  }

  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/devices?id=eq." + String(deviceId) + "&select=state";
  http.begin(url);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("apikey", supabaseKey);

  int httpCode = http.GET();
  String stateStatus = "";
  if (httpCode == 200) {
    String response = http.getString();
    DynamicJsonDocument doc(512);
    DeserializationError error = deserializeJson(doc, response);
    if (error) {
      Serial.print("deserializeJson() thất bại: "); Serial.println(error.c_str());
    } else if (doc.size() > 0 && doc[0]["state"].is<String>()) {
      stateStatus = doc[0]["state"].as<String>();
      Serial.println("Supabase đọc (id=" + String(deviceId) + "): state = " + stateStatus);
    } else {
      Serial.println("Phản hồi Supabase không hợp lệ (id=" + String(deviceId) + "): " + response);
    }
  } else {
    Serial.print("Đọc Supabase thất bại (id=" + String(deviceId) + "), mã HTTP: ");
    Serial.println(httpCode);
    Serial.println("Phản hồi: " + http.getString());
  }
  http.end();
  return stateStatus;
}

// Check door state from Supabase
void checkDoorState() {
  if (millis() - state.lastDoorCheck < DOOR_CHECK_INTERVAL) return;

  if (!connectWiFi()) return;

  String doorState = readDeviceStatus(DOOR_DEVICE_ID);
  if (doorState == "OPEN" && !state.servoActive) {
    Serial.println("Mở cửa đến 90 độ (Supabase)...");
    myServo.write(90);
    state.servoActive = true;
    state.servoMoveTime = millis();
    logHistory(DOOR_DEVICE_ID, "Cửa đã mở từ Supabase");
  } else if (doorState == "CLOSE" && state.servoActive) {
    Serial.println("Đóng cửa về 0 độ (Supabase)...");
    myServo.write(0);
    state.servoActive = false;
    state.servoMoveTime = 0;
    logHistory(DOOR_DEVICE_ID, "Cửa đã đóng từ Supabase");
  } else if (doorState != "") {
    Serial.println("Giá trị trạng thái Supabase không hợp lệ (door): " + doorState);
  }
  state.lastDoorCheck = millis();
}

// Handle RFID
void handleRFID() {
  if (millis() - state.lastRFIDCheck < RFID_CHECK_INTERVAL) return;
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    state.lastRFIDCheck = millis();
    return;
  }

  String cardUID = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    cardUID += String(rfid.uid.uidByte[i] < 0x10 ? "0" : "");
    cardUID += String(rfid.uid.uidByte[i], HEX);
    if (i < rfid.uid.size - 1) cardUID += " ";
  }
  cardUID.trim();
  cardUID.toUpperCase();

  Serial.print("UID thẻ: "); Serial.println(cardUID);

  if (cardUID == validUID) {
    Serial.println("Truy cập được cấp (RFID)! Mở cửa...");
    myServo.write(90);
    state.servoActive = true;
    state.servoMoveTime = millis();
    updateDeviceState("door", "OPEN");
    logHistory(DOOR_DEVICE_ID, "Truy cập RFID được cấp: " + cardUID);
  } else {
    Serial.println("Truy cập bị từ chối (RFID)!");
    logHistory(DOOR_DEVICE_ID, "Truy cập RFID bị từ chối: " + cardUID);
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  state.lastRFIDCheck = millis();
}

// Handle sensors (PZEM and DHT11)
void handleSensors() {
  if (millis() - state.lastSensorRead < SENSOR_READ_INTERVAL) return;

  Serial.println("\n=== Cập nhật dữ liệu cảm biến ===");
  Serial.println("------------------------");

  // Read DHT11
  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();
  if (!isnan(humidity)) {
    Serial.print("Độ ẩm: "); Serial.print(humidity, 1); Serial.println(" %");
    updateDeviceState("humidity", String(humidity, 1));
    logHistory(HUMIDITY_DEVICE_ID, "Độ ẩm cập nhật: " + String(humidity, 1) + "%");
  } else {
    Serial.println("Không thể đọc độ ẩm từ DHT11!");
  }
  if (!isnan(temperature)) {
    Serial.print("Nhiệt độ: "); Serial.print(temperature, 1); Serial.println(" °C");
    updateDeviceState("temperature", String(temperature, 1));
    logHistory(TEMPERATURE_DEVICE_ID, "Nhiệt độ cập nhật: " + String(temperature, 1) + "°C");
  } else {
    Serial.println("Không thể đọc nhiệt độ từ DHT11!");
  }

  // Read PZEM-004T
  float voltage = pzem.voltage();
  float current = pzem.current();
  float power = pzem.power();
  float energy = pzem.energy();
  float frequency = pzem.frequency();
  float pf = pzem.pf();

  Serial.println("------------------------");
  if (!isnan(voltage)) {
    Serial.print("Điện áp: "); Serial.print(voltage, 1); Serial.println(" V");
    updateDeviceState("voltage", String(voltage, 1));
    logHistory(VOLTAGE_DEVICE_ID, "Điện áp cập nhật: " + String(voltage, 1) + "V");
  } else {
    Serial.println("Lỗi khi đọc điện áp từ PZEM!");
  }
  if (!isnan(current)) {
    Serial.print("Dòng điện: "); Serial.print(current, 3); Serial.println(" A");
    updateDeviceState("current", String(current, 3));
    logHistory(CURRENT_DEVICE_ID, "Dòng điện cập nhật: " + String(current, 3) + "A");
  } else {
    Serial.println("Lỗi khi đọc dòng điện từ PZEM!");
  }
  if (!isnan(power)) {
    Serial.print("Công suất: "); Serial.print(power, 1); Serial.println(" W");
    logHistory(VOLTAGE_DEVICE_ID, "Công suất cập nhật: " + String(power, 1) + "W");
  } else {
    Serial.println("Lỗi khi đọc công suất từ PZEM!");
  }
  if (!isnan(energy)) {
    Serial.print("Năng lượng: "); Serial.print(energy, 2); Serial.println(" Wh");
    logHistory(VOLTAGE_DEVICE_ID, "Năng lượng cập nhật: " + String(energy, 2) + "Wh");
  } else {
    Serial.println("Lỗi khi đọc năng lượng từ PZEM!");
  }
  if (!isnan(frequency)) {
    Serial.print("Tần số: "); Serial.print(frequency, 1); Serial.println(" Hz");
    logHistory(VOLTAGE_DEVICE_ID, "Tần số cập nhật: " + String(frequency, 1) + "Hz");
  } else {
    Serial.println("Lỗi khi đọc tần số từ PZEM!");
  }
  if (!isnan(pf)) {
    Serial.print("Hệ số công suất: "); Serial.print(pf, 2); Serial.println("");
    logHistory(VOLTAGE_DEVICE_ID, "Hệ số công suất cập nhật: " + String(pf, 2));
  } else {
    Serial.println("Lỗi khi đọc hệ số công suất từ PZEM!");
  }
  Serial.println("------------------------\n");

  state.lastSensorRead = millis();
}

// Handle servo (door)
void handleServo() {
  if (state.servoActive && millis() - state.servoMoveTime >= SERVO_DELAY) {
    Serial.println("Tự động đóng cửa về 0 độ...");
    myServo.write(0);
    state.servoActive = false;
    state.servoMoveTime = 0;
    if (connectWiFi()) {
      updateDeviceState("door", "CLOSE");
      logHistory(DOOR_DEVICE_ID, "Cửa tự động đóng");
    } else {
      Serial.println("Không thể cập nhật trạng thái đóng cửa: Không có WiFi");
    }
  }
}

// Handle DHT11 temperature for LED D2 control
void handleDHT() {
  if (millis() - state.lastDHTRead < DHT_READ_INTERVAL) return;

  float temperature = dht.readTemperature();
  if (isnan(temperature)) {
    Serial.println("Lỗi đọc nhiệt độ DHT11");
  } else {
    Serial.print("Nhiệt độ: "); Serial.print(temperature, 1); Serial.println(" °C");
    if (temperature > TEMP_THRESHOLD) {
      if (!state.tempLedBlinking) {
        state.tempLedBlinking = true;
        Serial.println("Nhiệt độ > 30°C, LED D2 bắt đầu nhấp nháy");
        logHistory(LAMP_DEVICE_ID, "LED D2 nhấp nháy do nhiệt độ > 30°C");
      }
      // Nhấp nháy LED D2
      digitalWrite(LED_PIN, HIGH);
      delay(500);
      digitalWrite(LED_PIN, LOW);
      delay(500);
    } else {
      if (state.tempLedBlinking) {
        state.tempLedBlinking = false;
        digitalWrite(LED_PIN, LOW); // Tắt LED D2
        Serial.println("Nhiệt độ <= 30°C, LED D2 tắt");
        logHistory(LAMP_DEVICE_ID, "LED D2 tắt do nhiệt độ <= 30°C");
      }
    }
  }
  state.lastDHTRead = millis();
}

// Handle PIR sensor
void handlePIR() {
  static bool lastRelayState = false;

  // Skip PIR logic if Supabase override is active
  if (millis() < state.supabaseOverrideUntil) {
    return;
  }

  int pirState = digitalRead(PIR_PIN);
  if (pirState == HIGH && state.lastPirState == LOW && !state.motionDetected) {
    Serial.println("Phát hiện chuyển động!");
    state.motionDetected = true;
    state.lastMotionTime = millis();
    updateDeviceState("motion", "detected");
    logHistory(MOTION_DEVICE_ID, "Chuyển động được phát hiện");
  } else if (pirState == LOW && state.motionDetected) {
    Serial.println("Không còn chuyển động!");
    state.motionDetected = false;
    updateDeviceState("motion", "not_detected");
    logHistory(MOTION_DEVICE_ID, "Không phát hiện chuyển động");
  }

  // Update relay and LED based on PIR and manual state
  bool newRelayState = relayManualState || (state.motionDetected && (millis() - state.lastMotionTime < MOTION_TIMEOUT));
  
  if (newRelayState != relayState) {
    relayState = newRelayState;
    digitalWrite(RELAY_PIN, relayState ? LOW : HIGH); // Active-low relay
    digitalWrite(LED_SUPABASE_PIN, relayState ? HIGH : LOW); // LED D32 mirrors relay
    Serial.println(relayState ? "Relay BẬT (PIR hoặc thủ công)" : "Relay TẮT");
    updateRelayStatus(relayState ? "ON" : "OFF");
    updateLampStatus(relayState ? "ON" : "OFF");
    logHistory(LAMP_DEVICE_ID, relayState ? "LED D32 bật" : "LED D32 tắt");
    logHistory(RELAY_DEVICE_ID, relayState ? "Relay bật" : "Relay tắt");
  }

  state.lastPirState = pirState;
  lastRelayState = relayState;
}

// Handle TTP224, fan, and manual relay
void handleTTP224() {
  static int lastFanSpeed = -1;
  static bool lastFanState = false;
  static bool lastRelayManualState = false;

  // Check debounce interval
  if (millis() - state.lastTouchTime < DEBOUNCE_INTERVAL) {
    return;
  }

  // Read touch sensor states
  bool touch1 = digitalRead(TOUCH_PIN1);
  bool touch2 = digitalRead(TOUCH_PIN2);
  bool touch3 = digitalRead(TOUCH_PIN3);
  bool touch4 = digitalRead(TOUCH_PIN4);

  // Button 1 (GPIO 27): Turn fan ON
  if (touch1 && !state.touch1Last) {
    fanState = true;
    fanSpeed = 128; // Tốc độ mặc định khi bật
    analogWrite(FAN_PIN, fanSpeed);
    Serial.println("Quạt BẬT, Tốc độ: " + String(fanSpeed));
    if (lastFanState != fanState || lastFanSpeed != fanSpeed) {
      updateDeviceState("fan", String(fanSpeed));
      logHistory(FAN_DEVICE_ID, "Quạt bật, tốc độ: " + String(fanSpeed));
    }
    state.lastTouchTime = millis();
  }

  // Button 2 (GPIO 14): Turn fan OFF
  if (touch2 && !state.touch2Last) {
    fanState = false;
    fanSpeed = 0;
    digitalWrite(FAN_PIN, LOW);
    Serial.println("Quạt TẮT");
    if (lastFanState != fanState || lastFanSpeed != fanSpeed) {
      updateDeviceState("fan", String(fanSpeed));
      logHistory(FAN_DEVICE_ID, "Quạt tắt");
    }
    state.lastTouchTime = millis();
  }

  // Button 3 (GPIO 12): Increase speed
  if (touch3 && !state.touch3Last && fanState) {
    int currentLevel = 0;
    for (int i = 0; i <= maxLevel; i++) {
      if (fanSpeed == speedLevels[i]) {
        currentLevel = i;
        break;
      }
    }
    if (currentLevel < maxLevel) {
      fanSpeed = speedLevels[currentLevel + 1];
      analogWrite(FAN_PIN, fanSpeed);
      Serial.println("Tăng tốc độ quạt: " + String(fanSpeed));
      if (lastFanSpeed != fanSpeed) {
        updateDeviceState("fan", String(fanSpeed));
        logHistory(FAN_DEVICE_ID, "Tăng tốc độ quạt lên: " + String(fanSpeed));
      }
    }
    state.lastTouchTime = millis();
  }

  // Button 4 (GPIO 13): Toggle manual relay state
  if (touch4 && !state.touch4Last) {
    relayManualState = !relayManualState;
    Serial.println(relayManualState ? "Relay thủ công BẬT" : "Relay thủ công TẮT");
    if (lastRelayManualState != relayManualState) {
      updateRelayStatus(relayManualState ? "ON" : "OFF");
      logHistory(RELAY_DEVICE_ID, relayManualState ? "Relay thủ công bật" : "Relay thủ công tắt");
    }
    state.lastTouchTime = millis();
  }

  // Update previous states
  state.touch1Last = touch1;
  state.touch2Last = touch2;
  state.touch3Last = touch3;
  state.touch4Last = touch4;
  lastFanSpeed = fanSpeed;
  lastFanState = fanState;
  lastRelayManualState = relayManualState;
}

// Check Supabase for remote control
void checkSupabase() {
  if (millis() - state.lastSupabaseCheck < SUPABASE_CHECK_INTERVAL) return;

  // Read power state (id=4)
  String powerState = readDeviceStatus(RELAY_DEVICE_ID);
  bool currentRelayState = digitalRead(RELAY_PIN) == LOW; // Active-low
  bool powerStateOn = (powerState == "ON");
  if (powerState == "ON" || powerState == "OFF") {
    if (powerStateOn != currentRelayState) {
      Serial.println("Điều chỉnh relay từ Supabase: state = " + powerState);
      relayState = powerStateOn;
      relayManualState = powerStateOn;
      digitalWrite(RELAY_PIN, powerStateOn ? LOW : HIGH); // Active-low
      digitalWrite(LED_SUPABASE_PIN, powerStateOn ? HIGH : LOW); // LED D32 mirrors relay
      updateRelayStatus(powerStateOn ? "ON" : "OFF");
      updateLampStatus(powerStateOn ? "ON" : "OFF");
      logHistory(RELAY_DEVICE_ID, powerStateOn ? "Relay bật từ Supabase" : "Relay tắt từ Supabase");
      logHistory(LAMP_DEVICE_ID, powerStateOn ? "LED D32 bật từ Supabase" : "LED D32 tắt từ Supabase");
      state.supabaseOverrideUntil = millis() + SUPABASE_OVERRIDE_DURATION;
    }
  } else if (powerState != "") {
    Serial.println("Giá trị trạng thái Supabase không hợp lệ (power): " + powerState);
  }

  // Read lamp state (id=1)
  String lampState = readDeviceStatus(LAMP_DEVICE_ID);
  bool currentLedState = digitalRead(LED_SUPABASE_PIN) == HIGH; // Active-high
  bool lampStateOn = (lampState == "ON");
  if (lampState == "ON" || lampState == "OFF") {
    if (lampStateOn != currentLedState) {
      Serial.println("Điều chỉnh LED D32 từ Supabase: state = " + lampState);
      digitalWrite(LED_SUPABASE_PIN, lampStateOn ? HIGH : LOW); // Active-high
      updateLampStatus(lampStateOn ? "ON" : "OFF");
      logHistory(LAMP_DEVICE_ID, lampStateOn ? "LED D32 bật từ Supabase" : "LED D32 tắt từ Supabase");
    }
  } else if (lampState != "") {
    Serial.println("Giá trị trạng thái Supabase không hợp lệ (lamp): " + lampState);
  }

  // Read fan state (id=2)
  String fanStateStr = readDeviceStatus(FAN_DEVICE_ID);
  int supabaseFanSpeed = fanStateStr.toInt();
  if ((supabaseFanSpeed == 0 || supabaseFanSpeed == 128 || supabaseFanSpeed == 255) && supabaseFanSpeed != fanSpeed) {
    Serial.println("Điều chỉnh quạt từ Supabase: tốc độ = " + fanStateStr);
    fanSpeed = supabaseFanSpeed;
    fanState = (fanSpeed > 0);
    if (fanState) {
      analogWrite(FAN_PIN, fanSpeed);
    } else {
      digitalWrite(FAN_PIN, LOW);
    }
    updateDeviceState("fan", String(fanSpeed));
    logHistory(FAN_DEVICE_ID, fanState ? "Quạt bật từ Supabase, tốc độ: " + String(fanSpeed) : "Quạt tắt từ Supabase");
  } else if (fanStateStr != "" && supabaseFanSpeed != fanSpeed) {
    Serial.println("Giá trị trạng thái Supabase không hợp lệ (fan): " + fanStateStr);
  }

  state.lastSupabaseCheck = millis();
}

void setup() {
  Serial.begin(115200);
  Serial.println("Hệ thống IoT ESP32 - Khởi động...");

  // Connect to WiFi
  connectWiFi();

  // Initialize SPI and MFRC522
  SPI.begin();
  rfid.PCD_Init();
  Serial.println("RFID sẵn sàng");

  // Initialize DHT11
  dht.begin();
  Serial.println("DHT11 sẵn sàng");

  // Initialize Servo
  myServo.attach(SERVO_PIN, 500, 2500);
  myServo.write(0);
  Serial.println("Servo sẵn sàng");

  // Initialize Serial2 for PZEM-004T
  Serial2.begin(9600, SERIAL_8N1, PZEM_RX_PIN, PZEM_TX_PIN);
  delay(100); // Chờ PZEM ổn định
  if (pzem.resetEnergy()) {
    Serial.println("PZEM đặt lại năng lượng thành công");
  } else {
    Serial.println("Không thể đặt lại năng lượng PZEM");
  }

  // Test PZEM
  float testVoltage = pzem.voltage();
  float testCurrent = pzem.current();
  Serial.print("Điện áp kiểm tra: "); Serial.println(isnan(testVoltage) ? "Lỗi" : String(testVoltage, 1) + " V");
  Serial.print("Dòng điện kiểm tra: "); Serial.println(isnan(testCurrent) ? "Lỗi" : String(testCurrent, 3) + " A");

  // Initialize fan, TTP224, relay, LEDs, and PIR
  pinMode(FAN_PIN, OUTPUT);
  pinMode(TOUCH_PIN1, INPUT_PULLUP);
  pinMode(TOUCH_PIN2, INPUT_PULLUP);
  pinMode(TOUCH_PIN3, INPUT_PULLUP);
  pinMode(TOUCH_PIN4, INPUT_PULLUP);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  pinMode(LED_SUPABASE_PIN, OUTPUT);
  pinMode(PIR_PIN, INPUT);
  digitalWrite(FAN_PIN, LOW);      // Quạt tắt ban đầu
  digitalWrite(RELAY_PIN, HIGH);   // Relay tắt ban đầu (active-low)
  digitalWrite(LED_PIN, LOW);      // LED D2 tắt ban đầu
  digitalWrite(LED_SUPABASE_PIN, LOW); // LED D32 tắt ban đầu
  Serial.println("Quạt, TTP224, Relay, LEDs và PIR sẵn sàng");

  // Đợi PIR ổn định
  Serial.println("Đang chờ cảm biến PIR ổn định (30s)...");
  delay(30000); // Chờ 30 giây
  Serial.println("PIR ổn định hoàn tất");

  // Khởi tạo trạng thái trên Supabase
  updateRelayStatus("OFF");
  updateLampStatus("OFF");
  updateDeviceState("fan", "0");
  updateDeviceState("door", "CLOSE");

  // Debug initial TTP224 and PIR states
  Serial.println("Trạng thái TTP224 ban đầu:");
  Serial.print("Touch1 (Pin 27): "); Serial.println(digitalRead(TOUCH_PIN1));
  Serial.print("Touch2 (Pin 14): "); Serial.println(digitalRead(TOUCH_PIN2));
  Serial.print("Touch3 (Pin 12): "); Serial.println(digitalRead(TOUCH_PIN3));
  Serial.print("Touch4 (Pin 13): "); Serial.println(digitalRead(TOUCH_PIN4));
  Serial.print("PIR (Pin 3): "); Serial.println(digitalRead(PIR_PIN));
}

void loop() {
  handleTTP224();
  handlePIR();
  handleDHT();
  handleRFID();
  handleSensors();
  checkDoorState();
  handleServo();
  checkSupabase();
}