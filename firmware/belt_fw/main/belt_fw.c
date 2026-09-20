/*
 * Belt firmware: the ESP32 is a pure motor driver. The phone decides; this just obeys.
 *
 *   udp_rx_task  --(queue, length 1)-->  motor_task  -->  LEDC PWM  -->  L298N IN1..IN4
 *
 * udp_rx_task validates packets and overwrites the queue with the newest state. motor_task waits on
 * the queue with a BELT_HOLD_MS timeout: a packet applies immediately, and if none arrives in time
 * the wait expires and all motors go off. That one timeout is both "hold the last state briefly
 * rather than zeroing on one missed packet" and the failsafe if the phone or link dies mid-buzz.
 */
#include <stdbool.h>
#include <string.h>

#include "belt_config.h"
#include "belt_protocol.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "motors.h"
#include "wifi_ap.h"

static const char *TAG = "belt";

static QueueHandle_t s_state_queue; /* holds one belt_packet_t: the latest accepted state */

static inline int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static void udp_rx_task(void *arg)
{
    const int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (sock < 0) {
        ESP_LOGE(TAG, "socket() failed: errno %d", errno);
        vTaskDelete(NULL);
        return;
    }
    const struct sockaddr_in local = {
        .sin_family = AF_INET,
        .sin_port = htons(BELT_UDP_PORT),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    if (bind(sock, (const struct sockaddr *)&local, sizeof(local)) < 0) {
        ESP_LOGE(TAG, "bind() to port %d failed: errno %d", BELT_UDP_PORT, errno);
        close(sock);
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG, "listening for belt packets on UDP :%d", BELT_UDP_PORT);

    bool have_last = false;
    uint8_t last_seq = 0;
    int64_t last_applied_ms = 0;
    uint32_t rejected = 0, dropped = 0;

    for (;;) {
        uint8_t buffer[64];
        const int len = recvfrom(sock, buffer, sizeof(buffer), 0, NULL, NULL);
        if (len < 0) {
            ESP_LOGW(TAG, "recvfrom failed: errno %d", errno);
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        belt_packet_t packet;
        if (!belt_packet_parse(buffer, (size_t)len, &packet)) {
            rejected++;
            ESP_LOGW(TAG, "ignored malformed datagram (%d bytes, %lu so far)", len, (unsigned long)rejected);
            continue;
        }

        const int64_t now = now_ms();
        const uint32_t since = have_last ? (uint32_t)(now - last_applied_ms) : 0;
        if (!belt_should_apply(have_last, last_seq, packet.seq, since, BELT_HOLD_MS)) {
            dropped++;
            ESP_LOGW(TAG, "dropped out-of-order packet seq=%u (last applied %u, %lu so far)", packet.seq,
                     last_seq, (unsigned long)dropped);
            continue;
        }

        if (have_last && since <= BELT_HOLD_MS) {
            const uint8_t skipped = (uint8_t)(packet.seq - last_seq - 1); /* packets lost in between */
            if (skipped > 0) ESP_LOGD(TAG, "%u packet(s) lost before seq=%u", skipped, packet.seq);
        }
        have_last = true;
        last_seq = packet.seq;
        last_applied_ms = now;
        xQueueOverwrite(s_state_queue, &packet); /* never blocks: newest state replaces any unread one */
    }
}

static void motor_task(void *arg)
{
    gpio_config_t led = {
        .pin_bit_mask = 1ULL << BELT_STATUS_LED_GPIO,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&led);
    gpio_set_level(BELT_STATUS_LED_GPIO, 0);

    bool live = false;
    for (;;) {
        belt_packet_t state;
        if (xQueueReceive(s_state_queue, &state, pdMS_TO_TICKS(BELT_HOLD_MS)) == pdTRUE) {
            motors_set(state.zones);
            if (!live) {
                ESP_LOGI(TAG, "phone link live");
                live = true;
                gpio_set_level(BELT_STATUS_LED_GPIO, 1);
            }
            ESP_LOGD(TAG, "seq=%u zones=[%u %u %u %u]", state.seq, state.zones[0], state.zones[1],
                     state.zones[2], state.zones[3]);
        } else {
            motors_off(); /* hold window expired */
            if (live) {
                ESP_LOGW(TAG, "no packets for %d ms: motors off", BELT_HOLD_MS);
                live = false;
                gpio_set_level(BELT_STATUS_LED_GPIO, 0);
            }
        }
    }
}

void app_main(void)
{
    motors_init(); /* first, so the outputs are driven low as early as possible after boot */
    s_state_queue = xQueueCreate(1, sizeof(belt_packet_t));
    configASSERT(s_state_queue != NULL);

    wifi_ap_start();

    xTaskCreate(motor_task, "motor", 3072, NULL, 6, NULL); /* higher priority than the receiver */
    xTaskCreate(udp_rx_task, "udp_rx", 4096, NULL, 5, NULL);
}
