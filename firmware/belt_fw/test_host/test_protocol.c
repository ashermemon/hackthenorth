/* Host-side tests for belt_protocol.c. Run: firmware/belt_fw/test_host/run.sh */
#include <stdio.h>
#include <string.h>

#include "belt_protocol.h"

static int checks = 0, failures = 0;

#define CHECK(cond, msg)                                       \
    do {                                                       \
        checks++;                                              \
        if (!(cond)) {                                         \
            failures++;                                        \
            printf("  FAIL: %s (line %d)\n", msg, __LINE__);   \
        }                                                      \
    } while (0)

int main(void)
{
    belt_packet_t p;

    /* --- parsing --- */
    const uint8_t good[6] = {0xB7, 42, 0, 120, 255, 7};
    CHECK(belt_packet_parse(good, 6, &p), "valid packet parses");
    CHECK(p.seq == 42, "seq is byte 1");
    CHECK(p.zones[0] == 0 && p.zones[1] == 120 && p.zones[2] == 255 && p.zones[3] == 7,
          "zones are bytes 2-5 in order left hip -> right hip");

    const uint8_t badmagic[6] = {0x00, 1, 1, 1, 1, 1};
    CHECK(!belt_packet_parse(badmagic, 6, &p), "wrong magic rejected");
    CHECK(!belt_packet_parse(good, 5, &p), "too short rejected");
    CHECK(!belt_packet_parse(good, 7, &p), "too long rejected");
    CHECK(!belt_packet_parse(good, 0, &p), "empty rejected");
    CHECK(!belt_packet_parse(NULL, 6, &p), "NULL data rejected");
    CHECK(!belt_packet_parse(good, 6, NULL), "NULL out rejected");

    /* --- sequence comparison with wraparound --- */
    CHECK(belt_seq_is_newer(5, 4), "5 is newer than 4");
    CHECK(!belt_seq_is_newer(4, 5), "4 is not newer than 5");
    CHECK(!belt_seq_is_newer(5, 5), "a duplicate is not newer");
    CHECK(belt_seq_is_newer(0, 255), "0 is newer than 255 (wraparound)");
    CHECK(belt_seq_is_newer(3, 250), "3 is newer than 250 (wraparound)");
    CHECK(!belt_seq_is_newer(250, 3), "250 is not newer than 3");
    CHECK(belt_seq_is_newer(127 + 10, 10), "+127 is still newer");
    CHECK(!belt_seq_is_newer(128 + 10, 10), "+128 reads as older (int8 half-window)");

    /* --- accept/reject rule --- */
    CHECK(belt_should_apply(false, 0, 200, 0, 500), "first packet ever is applied");
    CHECK(belt_should_apply(true, 10, 11, 200, 500), "next packet in order is applied");
    CHECK(belt_should_apply(true, 10, 13, 200, 500), "a gap (lost packets) is still applied");
    CHECK(!belt_should_apply(true, 10, 9, 50, 500), "reordered packet is dropped");
    CHECK(!belt_should_apply(true, 10, 10, 50, 500), "duplicate is dropped");
    CHECK(belt_should_apply(true, 255, 0, 200, 500), "wraparound in order is applied");

    /* the phone app restarted: seq is back at 0 but the last applied was 50 */
    CHECK(!belt_should_apply(true, 50, 0, 200, 500), "restart looks stale while the belt is still live...");
    CHECK(belt_should_apply(true, 50, 0, 501, 500), "...but is accepted once nothing has applied for the hold window");
    CHECK(belt_should_apply(true, 50, 0, 5000, 500), "long silence then restart is accepted");
    CHECK(!belt_should_apply(true, 50, 49, 500, 500), "exactly at the boundary still counts as live");

    printf(failures == 0 ? "All %d checks passed.\n" : "%d checks, FAILURES: %d\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
