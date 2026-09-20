// Host-side tests for belt_pulse.h: simulates the clock one millisecond at a time.
// Run: firmware/belt_arduino/test_host/run.sh
#include <stdio.h>

#include <functional>
#include <vector>

#include "../belt_pulse.h"

static int checks = 0, failures = 0;

#define CHECK(cond, msg)                                     \
  do {                                                       \
    checks++;                                                \
    if (!(cond)) {                                           \
      failures++;                                            \
      printf("  FAIL: %s (line %d)\n", msg, __LINE__);       \
    }                                                        \
  } while (0)

// One motor's on/off for each millisecond, given the urgency at each moment.
static std::vector<bool> simulate(uint32_t startMs, uint32_t durationMs,
                                  const std::function<uint8_t(uint32_t)>& urgencyAt) {
  BeltPulse pulse;
  std::vector<bool> on;
  for (uint32_t i = 0; i < durationMs; i++) {
    const uint32_t now = startMs + i;  // wraps like millis()
    on.push_back(pulse.update(now, urgencyAt(i)));
  }
  return on;
}

struct Runs {
  int pulses = 0;                // rising edges
  uint32_t longestOn = 0;
  uint32_t shortestGap = 0xFFFFFFFF;  // between two pulses
  uint32_t onTotal = 0;
};

static Runs analyse(const std::vector<bool>& on) {
  Runs r;
  uint32_t onRun = 0, offRun = 0;
  bool seenPulse = false;
  for (size_t i = 0; i < on.size(); i++) {
    if (on[i]) {
      if (onRun == 0) {
        r.pulses++;
        if (seenPulse && offRun < r.shortestGap) r.shortestGap = offRun;
      }
      onRun++;
      r.onTotal++;
      offRun = 0;
      seenPulse = true;
      if (onRun > r.longestOn) r.longestOn = onRun;
    } else {
      onRun = 0;
      offRun++;
    }
  }
  return r;
}

int main() {
  // --- period mapping ---
  CHECK(beltPulsePeriodMs(1) == 1000, "urgency 1 is the slowest: 1 pulse per second");
  CHECK(beltPulsePeriodMs(254) >= 166 && beltPulsePeriodMs(254) <= 168, "urgency 254 is the fastest: ~6 per second");
  bool monotonic = true;
  for (int u = 2; u <= 254; u++) {
    if (beltPulsePeriodMs(u) > beltPulsePeriodMs(u - 1)) monotonic = false;
  }
  CHECK(monotonic, "higher urgency never means a slower pulse");
  const uint32_t mid = beltPulsePeriodMs(128);
  CHECK(mid >= 405 && mid <= 410, "the middle of the range is ~2.5 pulses per second (geometric, not the arithmetic 3.5)");
  // geometric: each step multiplies the rate by a constant, so the ratio between the ends splits evenly
  const double r1 = static_cast<double>(beltPulsePeriodMs(1)) / beltPulsePeriodMs(64);
  const double r2 = static_cast<double>(beltPulsePeriodMs(64)) / beltPulsePeriodMs(127);
  CHECK(r1 > 0.95 * r2 && r1 < 1.05 * r2, "equal steps in urgency give equal ratios in rate");
  CHECK(beltPulsePeriodMs(0) == beltPulsePeriodMs(1) && beltPulsePeriodMs(255) == beltPulsePeriodMs(254), "out-of-range urgency is clamped");
  CHECK(beltPulsePeriodMs(254) - BELT_PULSE_ON_MS >= 60, "even at the fastest rate the rest gap leaves the motor time to spin down");

  // --- off and solid ---
  {
    auto off = simulate(0, 10000, [](uint32_t) { return uint8_t(0); });
    CHECK(analyse(off).onTotal == 0, "urgency 0 never buzzes");
    auto solid = simulate(0, 10000, [](uint32_t) { return uint8_t(255); });
    CHECK(analyse(solid).onTotal == 10000, "urgency 255 is on the whole time");
  }

  // --- pulse shape ---
  {
    auto slow = analyse(simulate(0, 5000, [](uint32_t) { return uint8_t(1); }));
    CHECK(slow.pulses == 5, "1 pulse per second for 5 s = 5 pulses");
    CHECK(slow.longestOn == BELT_PULSE_ON_MS, "each pulse is exactly BELT_PULSE_ON_MS long");
    CHECK(slow.shortestGap == 1000 - BELT_PULSE_ON_MS, "the gap is the rest of the period");

    auto fast = analyse(simulate(0, 10000, [](uint32_t) { return uint8_t(254); }));
    CHECK(fast.pulses >= 59 && fast.pulses <= 61, "~6 pulses per second for 10 s = ~60 pulses");
    CHECK(fast.longestOn == BELT_PULSE_ON_MS, "pulses are the same length at the fastest rate");
    CHECK(fast.shortestGap >= 60, "and never closer together than 60 ms");
  }

  // --- a new obstacle buzzes immediately ---
  {
    BeltPulse pulse;
    CHECK(!pulse.update(5000, 0), "off while there is no obstacle");
    CHECK(pulse.update(5013, 40), "the very first tick of a new obstacle is a pulse, not a wait");
    CHECK(pulse.update(5013 + BELT_PULSE_ON_MS - 1, 40), "and it lasts the full pulse length");
    CHECK(!pulse.update(5013 + BELT_PULSE_ON_MS + 1, 40), "then rests");
  }
  {
    BeltPulse pulse;                      // solid -> pulsing also starts a fresh pulse
    CHECK(pulse.update(1000, 255), "solid is on");
    CHECK(pulse.update(1500, 200), "dropping from solid to pulsing starts a fresh pulse");
    CHECK(!pulse.update(1500 + BELT_PULSE_ON_MS + 5, 200), "which then follows the normal rhythm");
  }
  {
    BeltPulse pulse;                      // off in between resets it
    pulse.update(0, 100);
    pulse.update(20, 0);
    CHECK(pulse.update(4321, 100), "after being off, the next obstacle buzzes at once");
  }

  // --- changing rate mid-beat keeps the beat ---
  {
    auto on = simulate(0, 20000, [](uint32_t t) {          // urgency wanders 10..250 every 173 ms
      return static_cast<uint8_t>(10 + (t / 173) * 37 % 240);
    });
    Runs r = analyse(on);
    CHECK(r.longestOn <= BELT_PULSE_ON_MS, "a pulse is never stretched by a rate change");
    CHECK(r.shortestGap >= BELT_PULSE_MIN_GAP_MS, "and wandering rates never crowd pulses together");
    CHECK(r.pulses > 20, "and it keeps pulsing");
  }
  {
    // The invariant that matters: however a rate change lands, two pulses are never closer than the
    // minimum gap. Try a jump from 1 Hz to 6 Hz at every millisecond after the first pulse ends.
    uint32_t worstGap = 0xFFFFFFFF;
    for (uint32_t jumpAt = BELT_PULSE_ON_MS + 1; jumpAt <= 1300; jumpAt++) {
      auto on = simulate(0, 2500, [jumpAt](uint32_t t) { return t < jumpAt ? uint8_t(1) : uint8_t(254); });
      Runs r = analyse(on);
      if (r.shortestGap < worstGap) worstGap = r.shortestGap;
    }
    CHECK(worstGap >= BELT_PULSE_MIN_GAP_MS, "a rate jump at any moment never puts two pulses closer than the minimum gap");
    uint32_t worstGapDown = 0xFFFFFFFF;    // and the other direction, fast to slow
    for (uint32_t jumpAt = BELT_PULSE_ON_MS + 1; jumpAt <= 400; jumpAt++) {
      auto on = simulate(0, 3000, [jumpAt](uint32_t t) { return t < jumpAt ? uint8_t(254) : uint8_t(1); });
      Runs r = analyse(on);
      if (r.shortestGap < worstGapDown) worstGapDown = r.shortestGap;
    }
    CHECK(worstGapDown >= BELT_PULSE_MIN_GAP_MS, "same when slowing down");
  }

  // --- clock rollover, like millis() after ~49 days ---
  {
    auto on = analyse(simulate(0xFFFFFFFFu - 1500, 6000, [](uint32_t) { return uint8_t(1); }));
    CHECK(on.pulses == 6 && on.longestOn == BELT_PULSE_ON_MS, "keeps its rhythm across the millis() wraparound");
  }

  // --- the app's end-to-end range ---
  {
    // Urgency values the app's IntensityMapper produces with the default tuning (far 2.0 m, near
    // 0.5 m), computed from the Swift code, and the pulse rate each becomes here.
    struct { double meters; uint8_t urgency; double lo, hi; } cases[] = {
      {1.99, 2, 0.99, 1.03}, {1.6, 68, 1.55, 1.67}, {1.2, 135, 2.5, 2.65},
      {0.9, 186, 3.6, 3.8}, {0.7, 220, 4.6, 4.85}, {0.55, 245, 5.5, 5.75},
    };
    for (auto& c : cases) {
      const double hz = 1000.0 / beltPulsePeriodMs(c.urgency);
      char msg[112];
      snprintf(msg, sizeof msg, "%.2f m (urgency %u) pulses %.2f/s, expected %.2f-%.2f", c.meters, c.urgency, hz, c.lo, c.hi);
      CHECK(hz >= c.lo && hz <= c.hi, msg);
    }
  }

  printf(failures == 0 ? "All %d checks passed.\n" : "%d checks, FAILURES: %d\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
