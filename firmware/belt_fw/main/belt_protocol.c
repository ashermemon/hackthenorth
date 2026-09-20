#include "belt_protocol.h"

#include <string.h>

bool belt_packet_parse(const uint8_t *data, size_t len, belt_packet_t *out)
{
    if (data == NULL || out == NULL || len != BELT_PACKET_SIZE || data[0] != BELT_MAGIC) {
        return false;
    }
    out->seq = data[1];
    memcpy(out->zones, &data[2], BELT_ZONE_COUNT);
    return true;
}

bool belt_seq_is_newer(uint8_t seq, uint8_t last)
{
    return (int8_t)(uint8_t)(seq - last) > 0;
}

bool belt_should_apply(bool have_last, uint8_t last_seq, uint8_t seq,
                       uint32_t ms_since_last_applied, uint32_t hold_ms)
{
    if (!have_last) return true;
    if (ms_since_last_applied > hold_ms) return true;
    return belt_seq_is_newer(seq, last_seq);
}
