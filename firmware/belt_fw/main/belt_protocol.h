/*
 * Belt packet parsing and the accept/reject rule. Pure C with no ESP-IDF dependencies, so it is
 * unit-tested on the host (test_host/). Wire format: docs/PACKET_SPEC.md.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BELT_MAGIC 0xB7
#define BELT_PACKET_SIZE 6
#define BELT_ZONE_COUNT 4

typedef struct {
    uint8_t seq;
    uint8_t zones[BELT_ZONE_COUNT]; /* PWM duty 0-255: left hip, left pocket, right pocket, right hip */
} belt_packet_t;

/* True and fills `out` if the datagram is exactly 6 bytes starting with the magic byte. */
bool belt_packet_parse(const uint8_t *data, size_t len, belt_packet_t *out);

/* True if `seq` is newer than `last`, comparing with u8 wraparound (plain > breaks at 255 -> 0). */
bool belt_seq_is_newer(uint8_t seq, uint8_t last);

/*
 * Whether to apply a parsed packet. Drops reordered/duplicate packets (seq not newer than the last
 * applied one), EXCEPT when nothing has been applied for `hold_ms`: after that the belt is already
 * silent, so a phone-app restart (seq back at 0) must be accepted, not ignored for up to 128 packets.
 */
bool belt_should_apply(bool have_last, uint8_t last_seq, uint8_t seq,
                       uint32_t ms_since_last_applied, uint32_t hold_ms);
