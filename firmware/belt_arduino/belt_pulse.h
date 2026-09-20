/*
 * Turns a zone's urgency byte into a pulsing pattern. Plain C++ with no Arduino dependency, so the
 * timing is unit-tested on the Mac by simulating the clock (test_host/).
 *
 *   urgency 0        -> off
 *   urgency 1..254   -> pulses at BELT_PULSE_MIN_HZ .. BELT_PULSE_MAX_HZ (geometric steps)
 *   urgency 255      -> solid
 *
 * Every pulse is the same length (BELT_PULSE_ON_MS); only the gap between pulses changes with
 * urgency, so pulses stay crisp however fast they come. Rate is spaced geometrically because we
 * judge rates by ratio (1, 1.5, 2.5, 4, 6 Hz feel like even steps), not by difference.
 */
#pragma once

#include <math.h>
#include <stdint.h>

#include "belt_config.h"

constexpr uint8_t BELT_URGENCY_OFF = 0;
constexpr uint8_t BELT_URGENCY_SOLID = 255;

// Pulse period in ms for urgency 1..254 (values outside are clamped).
inline uint32_t beltPulsePeriodMs(uint8_t urgency) {
  if (urgency < 1) urgency = 1;
  if (urgency > 254) urgency = 254;
  const float t = static_cast<float>(urgency - 1) / 253.0f;  // 0 = slowest, 1 = fastest
  const float hz = BELT_PULSE_MIN_HZ * powf(BELT_PULSE_MAX_HZ / BELT_PULSE_MIN_HZ, t);
  return static_cast<uint32_t>(1000.0f / hz + 0.5f);
}

// One zone's pulse generator. Call update() often (every loop) with the zone's current urgency.
struct BeltPulse {
  uint32_t cycleStartMs = 0;
  uint32_t periodMs = 0;
  uint8_t lastUrgency = BELT_URGENCY_OFF;

  // Whether the motor should be on at `nowMs`. Keeps its place in the cycle when urgency changes
  // (so a rate change doesn't restart the beat), but a zone that was off or solid starts a fresh
  // pulse immediately, so a new obstacle buzzes at once instead of after a gap.
  bool update(uint32_t nowMs, uint8_t urgency) {
    if (urgency == BELT_URGENCY_OFF) {
      lastUrgency = BELT_URGENCY_OFF;
      return false;
    }
    if (urgency == BELT_URGENCY_SOLID) {
      lastUrgency = BELT_URGENCY_SOLID;
      return true;
    }

    const bool startFresh = lastUrgency == BELT_URGENCY_OFF || lastUrgency == BELT_URGENCY_SOLID;
    if (startFresh) cycleStartMs = nowMs;
    if (startFresh || urgency != lastUrgency) periodMs = beltPulsePeriodMs(urgency);
    lastUrgency = urgency;

    uint32_t elapsed = nowMs - cycleStartMs;  // unsigned: correct across millis() rollover
    if (elapsed >= periodMs) {
      elapsed %= periodMs;
      cycleStartMs = nowMs - elapsed;
    }
    // Pulses keep their full length, but never squeeze the rest gap below BELT_PULSE_MIN_GAP_MS
    // (matters only if the rates or pulse length are changed to something extreme).
    const uint32_t maxOnMs = periodMs > BELT_PULSE_MIN_GAP_MS ? periodMs - BELT_PULSE_MIN_GAP_MS : periodMs / 2;
    const uint32_t onMs = BELT_PULSE_ON_MS < maxOnMs ? BELT_PULSE_ON_MS : maxOnMs;
    return elapsed < onMs;
  }
};
