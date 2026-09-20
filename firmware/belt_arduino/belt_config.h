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
// The GPIO that drives each zone's motor, in the order the app sends the four bytes (z0..z3):
//   z0 far left (left hip), z1 inner left (left pocket), z2 inner right (right pocket), z3 far right (right hip).
// The belt as built has its motors in a different order from the original plan (GPIOs 33, 25, 26, 27
// drive, respectively, the inner-left, far-left, far-right and inner-right motors), so this table is
// deliberately not in pin order. If a motor is ever rewired, change it here, never in the app.
static const int BELT_ZONE_GPIOS[4] = {25, 33, 27, 26};

// PWM carrier for the motor drive (not the pulse rate below). 10 kHz is above where PWM ripple is
// felt, mostly above motor noise, and well within what the L298N (a slow driver) switches cleanly.
#define BELT_PWM_FREQ_HZ 10000
#define BELT_PWM_RESOLUTION_BITS 8  // duty 0..255

// ---- Feel: pulses, not strength -------------------------------------------------------------
// The byte the phone sends per zone is URGENCY, not motor strength: 0 = off, 255 = solid buzz, and
// 1..254 = pulses that come faster the closer the obstacle. Every pulse drives the motor at the
// same strength, so it always starts crisply, at any rotor angle, with no dead zone to tune.
// (belt_pulse.h has the details.)
#define BELT_PULSE_DUTY 200    // motor strength during a pulse (and while solid), 0..255. Tune by feel.
#define BELT_PULSE_ON_MS 90    // length of each pulse; the gap between pulses is what changes
#define BELT_PULSE_MIN_HZ 1.0f // slowest pulse rate (obstacle at the edge of range)
#define BELT_PULSE_MAX_HZ 6.0f // fastest before pulses blur together: a motor takes ~50-100 ms to
                               // spin up and down
#define BELT_PULSE_MIN_GAP_MS 60  // never rest less than this between pulses, whatever the rate
// Safety cap on motor strength, in case a motor turns out to be rated lower than the supply
// gives it. BELT_PULSE_DUTY is limited to this.
#define BELT_MAX_DUTY 255

// ---- Status LED ----------------------------------------------------------------------------
// Onboard LED (GPIO 2 on the DOIT ESP32 DevKit V1):
//   fast blink   = joining the hotspot
//   short flash every 2 s = joined, waiting for the phone
//   solid on     = packets arriving
#define BELT_STATUS_LED_GPIO 2
