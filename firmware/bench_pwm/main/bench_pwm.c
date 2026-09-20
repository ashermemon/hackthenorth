#include <WiFi.h>
#include <WiFiUdp.h>

const char* ssid = "BlindSight";
const char* password = "everest1";
const int udpPort = 4210; 

WiFiUDP udp;

const int NUM_ZONES = 4;
const int ZONE_GPIO[NUM_ZONES] = {33, 25, 26, 27}; 

// Timeout Logic Variables
unsigned long lastPacketTime = 0;
const unsigned long TIMEOUT_MS = 500; 
bool motorsActive = false;

void setup() {
  Serial.begin(115200);

  // Initialize PWM for motors
  for (int z = 0; z < NUM_ZONES; z++) {
    ledcAttach(ZONE_GPIO[z], 5000, 8); 
    ledcWrite(ZONE_GPIO[z], 0);
  }

  // Connect to the Hotspot
  Serial.print("Connecting to hotspot ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  Serial.println("\nWiFi connected!");
  Serial.print("ESP32 IP Address: ");
  Serial.println(WiFi.localIP()); // <-- THIS IS THE IP YOU GIVE TO EVEREST

  udp.begin(udpPort);
}

void loop() {
  int packetSize = udp.parsePacket();
  
  if (packetSize) {
    uint8_t packetBuffer[6]; 
    int len = udp.read(packetBuffer, 6);
    
    // Validate: Must be exactly 6 bytes AND start with the 0xB7 magic byte
    if (len == 6 && packetBuffer[0] == 0xB7) {
      
      // packetBuffer[1] is the sequence number (ignoring for now)
      
      // Apply intensity directly from the array bytes
      ledcWrite(ZONE_GPIO[0], packetBuffer[2]); // z0
      ledcWrite(ZONE_GPIO[1], packetBuffer[3]); // z1
      ledcWrite(ZONE_GPIO[2], packetBuffer[4]); // z2
      ledcWrite(ZONE_GPIO[3], packetBuffer[5]); // z3
      
      lastPacketTime = millis(); 
      motorsActive = true;
    }
  }

  // The "Missed Packet" Hold State
  if (motorsActive && (millis() - lastPacketTime > TIMEOUT_MS)) {
    for (int z = 0; z < NUM_ZONES; z++) {
      ledcWrite(ZONE_GPIO[z], 0); 
    }
    motorsActive = false;
    Serial.println("Connection lost: Motors zeroed after 500ms hold.");
  }
}