/*
 * PWM bench test for the belt's 4 L298N outputs. No WiFi, no packets.
 *
 * Drives GPIO -> L298N IN1..IN4 with LEDC PWM (ENA/ENB jumpered on) and lets you
 * poke each channel from the serial monitor (single keypresses, no Enter needed).
 * Answers the PRD's flagged risk: is PWM on the IN pins smooth and independent?
 *
 * Zone order matches docs/PACKET_SPEC.md: left hip, left pocket, right pocket, right hip.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "driver/ledc.h"
#include "driver/uart.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define NUM_ZONES 4

/* GPIOs wired to L298N IN1..IN4. Chosen to avoid strapping/flash pins and boot-time glitches. */
static const int ZONE_GPIO[NUM_ZONES] = {33, 25, 26, 27};
static const char *const ZONE_NAME[NUM_ZONES] = {"left hip", "left pocket", "right pocket", "right hip"};

#define LEDC_MODE LEDC_LOW_SPEED_MODE
#define LEDC_TIMER LEDC_TIMER_0
#define LEDC_RES LEDC_TIMER_8_BIT /* duty 0..255, same scale as the packet */

static const uint32_t FREQS_HZ[] = {500, 1000, 2000, 5000, 10000, 20000};
#define NUM_FREQS (sizeof(FREQS_HZ) / sizeof(FREQS_HZ[0]))
#define DEFAULT_FREQ_IDX 3 /* 5 kHz */

#define DUTY_STEP_COARSE 10
#define DUTY_STEP_FINE 1
#define RAMP_STEP 5
#define RAMP_STEP_MS 400

static uint8_t s_duty[NUM_ZONES];
static int s_freq_idx = DEFAULT_FREQ_IDX;
static int s_sel; /* selected zone for manual control */

static void set_duty(int zone, int duty)
{
    if (duty < 0) duty = 0;
    if (duty > 255) duty = 255;
    s_duty[zone] = (uint8_t)duty;
    ledc_set_duty(LEDC_MODE, (ledc_channel_t)(LEDC_CHANNEL_0 + zone), (uint32_t)duty);
    ledc_update_duty(LEDC_MODE, (ledc_channel_t)(LEDC_CHANNEL_0 + zone));
}

static void all_off(void)
{
    for (int z = 0; z < NUM_ZONES; z++) set_duty(z, 0);
}

static void pwm_init(void)
{
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_MODE,
        .duty_resolution = LEDC_RES,
        .timer_num = LEDC_TIMER,
        .freq_hz = FREQS_HZ[s_freq_idx],
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));

    for (int z = 0; z < NUM_ZONES; z++) {
        const ledc_channel_config_t ch = {
            .gpio_num = ZONE_GPIO[z],
            .speed_mode = LEDC_MODE,
            .channel = (ledc_channel_t)(LEDC_CHANNEL_0 + z),
            .intr_type = LEDC_INTR_DISABLE,
            .timer_sel = LEDC_TIMER,
            .duty = 0,
            .hpoint = 0,
        };
        ESP_ERROR_CHECK(ledc_channel_config(&ch));
    }
}

static void next_freq(void)
{
    s_freq_idx = (s_freq_idx + 1) % NUM_FREQS;
    ESP_ERROR_CHECK(ledc_set_freq(LEDC_MODE, LEDC_TIMER, FREQS_HZ[s_freq_idx]));
    for (int z = 0; z < NUM_ZONES; z++) set_duty(z, s_duty[z]); /* re-latch duties after the divider changes */
    printf("PWM frequency: %u Hz\n", (unsigned)FREQS_HZ[s_freq_idx]);
}

/* Returns the pressed key, or -1 if none arrived within `ms`. */
static int read_key(uint32_t ms)
{
    uint8_t c;
    if (uart_read_bytes(UART_NUM_0, &c, 1, pdMS_TO_TICKS(ms)) == 1) return c;
    return -1;
}

/* Waits `ms`; returns true if a key was pressed (used to abort auto sequences). */
static bool wait_or_key(uint32_t ms)
{
    return read_key(ms) >= 0;
}

static void print_status(void)
{
    printf("freq=%u Hz  selected=%d (%s)\n", (unsigned)FREQS_HZ[s_freq_idx], s_sel + 1, ZONE_NAME[s_sel]);
    for (int z = 0; z < NUM_ZONES; z++) {
        printf("  zone %d %-12s GPIO%-2d duty=%3u%s\n", z + 1, ZONE_NAME[z], ZONE_GPIO[z], s_duty[z],
               z == s_sel ? "  <" : "");
    }
}

static void print_help(void)
{
    printf("\n--- PWM bench (press a key, no Enter) ---\n"
           " 1-4  select zone        + / -   duty +10 / -10 on selected zone\n"
           " ] / [ duty +1 / -1      0       selected zone off      z  all off\n"
           " f    next PWM frequency a       auto-ramp selected zone 0->255->0 (any key stops)\n"
           " t    independence test  s       status                 h  this help\n"
           "-----------------------------------------\n");
}

/* Ramp the selected zone up then down, printing each duty so you can note where it starts/stops buzzing. */
static void auto_ramp(void)
{
    printf("Ramping zone %d (%s) at %u Hz. Note the duty where it FIRST buzzes going up and where it STOPS going down.\n",
           s_sel + 1, ZONE_NAME[s_sel], (unsigned)FREQS_HZ[s_freq_idx]);
    all_off();
    bool aborted = false;
    for (int d = 0; d <= 255 && !aborted; d += RAMP_STEP) {
        set_duty(s_sel, d);
        printf("  up   duty=%3d\n", d);
        aborted = wait_or_key(RAMP_STEP_MS);
    }
    for (int d = 255; d >= 0 && !aborted; d -= RAMP_STEP) {
        set_duty(s_sel, d);
        printf("  down duty=%3d\n", d);
        aborted = wait_or_key(RAMP_STEP_MS);
    }
    all_off();
    printf(aborted ? "Ramp aborted.\n" : "Ramp done.\n");
}

/* Holds a pattern for `ms`; returns true if aborted by a keypress. */
static bool hold_pattern(const char *label, const uint8_t pattern[NUM_ZONES], uint32_t ms)
{
    printf("  %s: [%3u %3u %3u %3u]\n", label, pattern[0], pattern[1], pattern[2], pattern[3]);
    for (int z = 0; z < NUM_ZONES; z++) set_duty(z, pattern[z]);
    return wait_or_key(ms);
}

/* Independence test: one zone alone at a time, then 4 distinct strengths at once, in both orders. */
static void independence_test(void)
{
    printf("Independence test (any key aborts). Only the named zone should buzz in phase 1.\n");
    all_off();
    bool aborted = false;

    printf("Phase 1: each zone alone at full duty\n");
    for (int z = 0; z < NUM_ZONES && !aborted; z++) {
        uint8_t p[NUM_ZONES] = {0};
        p[z] = 255;
        char label[32];
        snprintf(label, sizeof(label), "zone %d only", z + 1);
        aborted = hold_pattern(label, p, 2500);
    }

    if (!aborted) {
        printf("Phase 2: four distinct strengths at once (should feel clearly different)\n");
        const uint8_t up[NUM_ZONES] = {64, 128, 192, 255};
        const uint8_t down[NUM_ZONES] = {255, 192, 128, 64};
        aborted = hold_pattern("weak->strong", up, 4000) || hold_pattern("strong->weak", down, 4000);
    }

    if (!aborted) {
        printf("Phase 3: neighbours off/on (does an idle motor next to a busy one twitch?)\n");
        const uint8_t a[NUM_ZONES] = {255, 0, 255, 0};
        const uint8_t b[NUM_ZONES] = {0, 255, 0, 255};
        aborted = hold_pattern("zones 1+3", a, 3000) || hold_pattern("zones 2+4", b, 3000);
    }

    all_off();
    printf(aborted ? "Test aborted.\n" : "Test done.\n");
}

static void adjust(int delta)
{
    set_duty(s_sel, s_duty[s_sel] + delta);
    printf("zone %d (%s) duty=%u\n", s_sel + 1, ZONE_NAME[s_sel], s_duty[s_sel]);
}

static void bench_task(void *arg)
{
    ESP_ERROR_CHECK(uart_driver_install(UART_NUM_0, 256, 0, 0, NULL, 0));
    pwm_init();
    print_help();
    print_status();

    for (;;) {
        int c = read_key(1000);
        switch (c) {
        case '1': case '2': case '3': case '4':
            s_sel = c - '1';
            printf("selected zone %d (%s), duty=%u\n", s_sel + 1, ZONE_NAME[s_sel], s_duty[s_sel]);
            break;
        case '+': case '=': adjust(DUTY_STEP_COARSE); break;
        case '-': case '_': adjust(-DUTY_STEP_COARSE); break;
        case ']': adjust(DUTY_STEP_FINE); break;
        case '[': adjust(-DUTY_STEP_FINE); break;
        case '0': set_duty(s_sel, 0); printf("zone %d off\n", s_sel + 1); break;
        case 'z': all_off(); printf("all off\n"); break;
        case 'f': next_freq(); break;
        case 'a': auto_ramp(); break;
        case 't': independence_test(); break;
        case 's': print_status(); break;
        case 'h': case '?': print_help(); break;
        default: break; /* timeout, Enter, or unknown key */
        }
    }
}

void app_main(void)
{
    xTaskCreate(bench_task, "bench", 4096, NULL, 5, NULL);
}
