/*
 * Every tunable in one place. Hotspot name and password are NOT here: they live in secrets.h,
 * which is git-ignored (copy secrets.example.h to secrets.h).
 */
#pragma once

// ---- Network -------------------------------------------------------------------------------
// The ESP32 joins the phone's Personal Hotspot as a client. An iPhone hotspot always uses
// 172.20.10.0/28 with the phone at .1, so a fixed address in that range never changes between
// sessions and the app can default to it. Set BELT_USE_STATIC_IP to 0 to take whatever the
// hotspot hands out instead (the address is printed on the serial monitor), e.g. for a hotspot
// that isn't an iPhone.
#define BELT_USE_STATIC_IP 1
#define BELT_STATIC_IP_OCTETS 172, 20, 10, 13
#define BELT_GATEWAY_OCTETS 172, 20, 10, 1
#define BELT_SUBNET_OCTETS 255, 255, 255, 240

#define BELT_UDP_PORT 4210

// Retry joining the hotspot this often while disconnected.
#define BELT_WIFI_RETRY_MS 10000

// ---- Safety --------------------------------------------------------------------------------
// No valid packet for this long -> all motors off. Also the "hold the last state briefly" window:
// one missed packet at 5 Hz (200 ms) changes nothing.
#define BELT_HOLD_MS 500

// ---- Motors --------------------------------------------------------------------------------
// GPIOs wired to L298N IN1..IN4, in zone order: left hip, left pocket, right pocket, right hip.
static const int BELT_ZONE_GPIOS[4] = {33, 25, 26, 27};

// PWM. 5 kHz is above where PWM ripple is felt as vibration, and low enough for the L298N (a slow
// driver) to switch cleanly. If the whine bothers you, try 20 kHz and check the buzz stays strong.
#define BELT_PWM_FREQ_HZ 5000
#define BELT_PWM_RESOLUTION_BITS 8  // duty 0..255, the packet's scale
// Safety cap on duty, in case a motor turns out to be rated lower than the supply gives it.
#define BELT_MAX_DUTY 255

// ---- Status LED ----------------------------------------------------------------------------
// Onboard LED (GPIO 2 on the DOIT ESP32 DevKit V1):
//   fast blink   = joining the hotspot
//   short flash every 2 s = joined, waiting for the phone
//   solid on     = packets arriving
#define BELT_STATUS_LED_GPIO 2
