/* The four L298N inputs, driven by LEDC PWM. No decisions here: duty in, vibration out. */
#pragma once

#include <stdint.h>

#include "belt_protocol.h"

/* Configures the timer and channels. Motors start off. */
void motors_init(void);

/* Applies one duty per zone (0-255), clamped to BELT_MAX_DUTY. */
void motors_set(const uint8_t zones[BELT_ZONE_COUNT]);

void motors_off(void);
