/*
 * Belt packet parsing and the accept/reject rule. Plain C++ with no Arduino dependency, so it is
 * unit-tested on the Mac (test_host/). Wire format: docs/PACKET_SPEC.md.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

constexpr uint8_t BELT_MAGIC = 0xB7;
constexpr size_t BELT_PACKET_SIZE = 6;
constexpr int BELT_ZONE_COUNT = 4;

struct BeltPacket {
  uint8_t seq;
  uint8_t zones[BELT_ZONE_COUNT];  // PWM duty 0-255: left hip, left pocket, right pocket, right hip
};

// True and fills `out` if the datagram is exactly 6 bytes starting with the magic byte.
inline bool beltPacketParse(const uint8_t* data, size_t len, BeltPacket* out) {
  if (data == nullptr || out == nullptr || len != BELT_PACKET_SIZE || data[0] != BELT_MAGIC) {
    return false;
  }
  out->seq = data[1];
  memcpy(out->zones, &data[2], BELT_ZONE_COUNT);
  return true;
}

// True if `seq` is newer than `last`, comparing with u8 wraparound (a plain > breaks at 255 -> 0).
inline bool beltSeqIsNewer(uint8_t seq, uint8_t last) {
  return static_cast<int8_t>(static_cast<uint8_t>(seq - last)) > 0;
}

// Whether to apply a parsed packet. Drops reordered/duplicate packets (seq not newer than the
// last applied one), EXCEPT when nothing has been applied for `holdMs`: after that the belt is
// already silent, so a phone-app restart (seq back at 0) must be accepted, not ignored for up to
// 128 packets.
inline bool beltShouldApply(bool haveLast, uint8_t lastSeq, uint8_t seq,
                            uint32_t msSinceLastApplied, uint32_t holdMs) {
  if (!haveLast) return true;
  if (msSinceLastApplied > holdMs) return true;
  return beltSeqIsNewer(seq, lastSeq);
}
