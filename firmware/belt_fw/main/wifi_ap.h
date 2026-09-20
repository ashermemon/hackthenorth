#pragma once

/* Starts the ESP32's own WiFi network (SoftAP) at 192.168.4.1. Blocks only until it is configured. */
void wifi_ap_start(void);
