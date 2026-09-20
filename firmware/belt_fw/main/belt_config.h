/*
 * Every tunable in one place. Placeholders marked BENCH are to be set from the
 * firmware/bench_pwm results.
 */
#pragma once

/* WiFi: the ESP32 hosts its own network; the phone joins it. AP address is 192.168.4.1. */
#define BELT_WIFI_SSID "BeltNav"
#define BELT_WIFI_PASSWORD "beltbelt1" /* WPA2 needs 8+ characters */
#define BELT_WIFI_CHANNEL 6            /* 1, 6 or 11; move if the room is crowded */
#define BELT_WIFI_MAX_CLIENTS 2

/* UDP listener (docs/PACKET_SPEC.md) */
#define BELT_UDP_PORT 4210

/* No valid packet for this long -> all motors off. Also the "hold last state briefly" window:
 * one missed packet at 5 Hz (200 ms) changes nothing. */
#define BELT_HOLD_MS 500

/* GPIOs wired to L298N IN1..IN4, zone order left hip, left pocket, right pocket, right hip. */
#define BELT_ZONE_GPIOS {33, 25, 26, 27}

/* Onboard LED (GPIO2 on the DOIT DevKit V1): on while packets are arriving, off when idle. */
#define BELT_STATUS_LED_GPIO 2

/* PWM (BENCH: pick the quietest frequency that still feels strongest) */
#define BELT_PWM_FREQ_HZ 5000
/* BENCH: safety cap so an unknown-rated motor can't be driven harder than it should be. */
#define BELT_MAX_DUTY 255
