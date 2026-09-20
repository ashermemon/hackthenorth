/*
 * Belt firmware: the ESP32 is a pure motor driver. The phone decides; this just obeys.
 *
 * Joins the phone's Personal Hotspot, listens for 6-byte UDP packets (docs/PACKET_SPEC.md), and
 * drives the four L298N inputs with PWM. If no valid packet arrives for BELT_HOLD_MS, every motor
 * goes off, which is both "hold the last state briefly instead of zeroing on one missed packet"
 * and the failsafe for a dead phone, app or link. Needs the Arduino-ESP32 core 3.x (uses the
 * ledcAttach(pin, freq, bits) API).
 */
#include <WiFi.h>
#include <WiFiUdp.h>

#include "belt_config.h"
#include "belt_protocol.h"

#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy secrets.example.h to secrets.h and fill in your hotspot name and password."
#endif

WiFiUDP udp;

bool wasConnected = false;
uint32_t lastWifiAttemptMs = 0;

bool haveLast = false;        // has any packet been applied yet (since the link came up)?
uint8_t lastSeq = 0;          // seq of the last applied packet
uint32_t lastAppliedMs = 0;   // when it was applied
bool motorsActive = false;

uint32_t rejectedCount = 0;   // malformed datagrams
uint32_t droppedCount = 0;    // valid but out-of-order packets

void setMotors(const uint8_t zones[BELT_ZONE_COUNT]) {
  for (int z = 0; z < BELT_ZONE_COUNT; z++) {
    uint32_t duty = zones[z];
    if (duty > BELT_MAX_DUTY) duty = BELT_MAX_DUTY;
    ledcWrite(BELT_ZONE_GPIOS[z], duty);
  }
}

void motorsOff() {
  for (int z = 0; z < BELT_ZONE_COUNT; z++) ledcWrite(BELT_ZONE_GPIOS[z], 0);
}

void startWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);  // power saving adds tens of ms of latency
  WiFi.setAutoReconnect(true);
#if BELT_USE_STATIC_IP
  WiFi.config(IPAddress(BELT_STATIC_IP_OCTETS), IPAddress(BELT_GATEWAY_OCTETS),
              IPAddress(BELT_SUBNET_OCTETS));
#endif
  WiFi.begin(BELT_WIFI_SSID, BELT_WIFI_PASSWORD);
  lastWifiAttemptMs = millis();
}

// Tracks joining and losing the hotspot. Losing it silences the motors at once.
void serviceWifi() {
  const bool connected = WiFi.status() == WL_CONNECTED;

  if (connected && !wasConnected) {
    Serial.printf("Joined hotspot. Belt is at %s:%d\n", WiFi.localIP().toString().c_str(),
                  BELT_UDP_PORT);
    udp.stop();  // rebind after every (re)join so the socket is never left stale
    udp.begin(BELT_UDP_PORT);
    haveLast = false;
  } else if (!connected && wasConnected) {
    Serial.println("Lost hotspot: motors off.");
    motorsOff();
    motorsActive = false;
  }
  wasConnected = connected;

  if (!connected && millis() - lastWifiAttemptMs > BELT_WIFI_RETRY_MS) {
    Serial.println("Still not on the hotspot, retrying...");
    WiFi.disconnect();
    WiFi.begin(BELT_WIFI_SSID, BELT_WIFI_PASSWORD);
    lastWifiAttemptMs = millis();
  }
}

// Reads at most one datagram and applies it if it is valid and in order.
void servicePackets() {
  const int size = udp.parsePacket();
  if (size <= 0) return;

  uint8_t buffer[64];
  const int len = udp.read(buffer, sizeof(buffer));
  // Drain whatever is left of an oversized datagram: parsePacket() returns 0 while unread data
  // remains, so leaving it would stall reception. (available()/read() behave the same on every
  // core version, unlike flush()/clear(), whose meaning changed.)
  while (udp.available()) udp.read();

  BeltPacket packet;
  if (size != static_cast<int>(BELT_PACKET_SIZE) || len != size ||
      !beltPacketParse(buffer, static_cast<size_t>(len), &packet)) {
    rejectedCount++;
    Serial.printf("Ignored malformed datagram (%d bytes, %lu so far)\n", size,
                  static_cast<unsigned long>(rejectedCount));
    return;
  }

  const uint32_t now = millis();
  const uint32_t since = haveLast ? now - lastAppliedMs : 0;
  if (!beltShouldApply(haveLast, lastSeq, packet.seq, since, BELT_HOLD_MS)) {
    droppedCount++;
    Serial.printf("Dropped out-of-order packet seq=%u (last applied %u, %lu so far)\n", packet.seq,
                  lastSeq, static_cast<unsigned long>(droppedCount));
    return;
  }

  haveLast = true;
  lastSeq = packet.seq;
  lastAppliedMs = now;
  setMotors(packet.zones);
  if (!motorsActive) Serial.println("Phone link live.");
  motorsActive = true;
}

// The failsafe: nothing valid for BELT_HOLD_MS -> silence.
void serviceHoldTimeout() {
  if (motorsActive && millis() - lastAppliedMs > BELT_HOLD_MS) {
    motorsOff();
    motorsActive = false;
    Serial.printf("No packets for %d ms: motors off.\n", BELT_HOLD_MS);
  }
}

void serviceLed() {
  const uint32_t t = millis();
  bool on;
  if (WiFi.status() != WL_CONNECTED) {
    on = (t / 100) % 2 == 0;  // fast blink: joining
  } else if (motorsActive) {
    on = true;                // solid: packets arriving
  } else {
    on = (t % 2000) < 100;    // brief flash every 2 s: joined, waiting for the phone
  }
  digitalWrite(BELT_STATUS_LED_GPIO, on ? HIGH : LOW);
}

void setup() {
  Serial.begin(115200);
  pinMode(BELT_STATUS_LED_GPIO, OUTPUT);

  // Motors first, so the outputs are driven low as early as possible after boot.
  for (int z = 0; z < BELT_ZONE_COUNT; z++) {
    ledcAttach(BELT_ZONE_GPIOS[z], BELT_PWM_FREQ_HZ, BELT_PWM_RESOLUTION_BITS);
    ledcWrite(BELT_ZONE_GPIOS[z], 0);
  }

  Serial.printf("Belt firmware starting. Joining \"%s\"...\n", BELT_WIFI_SSID);
  startWifi();
}

void loop() {
  serviceWifi();
  if (WiFi.status() == WL_CONNECTED) servicePackets();
  serviceHoldTimeout();
  serviceLed();
  delay(1);  // yield; costs at most 1 ms of latency
}
