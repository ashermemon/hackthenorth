#include "motors.h"

#include "belt_config.h"
#include "driver/ledc.h"

#define LEDC_MODE LEDC_LOW_SPEED_MODE
#define LEDC_TIMER LEDC_TIMER_0

static const int s_gpios[BELT_ZONE_COUNT] = BELT_ZONE_GPIOS;

void motors_init(void)
{
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_MODE,
        .duty_resolution = LEDC_TIMER_8_BIT, /* duty 0..255, the packet's scale */
        .timer_num = LEDC_TIMER,
        .freq_hz = BELT_PWM_FREQ_HZ,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));

    for (int z = 0; z < BELT_ZONE_COUNT; z++) {
        const ledc_channel_config_t channel = {
            .gpio_num = s_gpios[z],
            .speed_mode = LEDC_MODE,
            .channel = (ledc_channel_t)(LEDC_CHANNEL_0 + z),
            .intr_type = LEDC_INTR_DISABLE,
            .timer_sel = LEDC_TIMER,
            .duty = 0,
            .hpoint = 0,
        };
        ESP_ERROR_CHECK(ledc_channel_config(&channel));
    }
}

void motors_set(const uint8_t zones[BELT_ZONE_COUNT])
{
    for (int z = 0; z < BELT_ZONE_COUNT; z++) {
        uint32_t duty = zones[z];
        if (duty > BELT_MAX_DUTY) duty = BELT_MAX_DUTY;
        ledc_set_duty(LEDC_MODE, (ledc_channel_t)(LEDC_CHANNEL_0 + z), duty);
        ledc_update_duty(LEDC_MODE, (ledc_channel_t)(LEDC_CHANNEL_0 + z));
    }
}

void motors_off(void)
{
    const uint8_t off[BELT_ZONE_COUNT] = {0, 0, 0, 0};
    motors_set(off);
}
