#include "wifi_ap.h"

#include <string.h>

#include "belt_config.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

static const char *TAG = "wifi_ap";

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (id == WIFI_EVENT_AP_STACONNECTED) {
        const wifi_event_ap_staconnected_t *e = data;
        ESP_LOGI(TAG, "phone joined: " MACSTR, MAC2STR(e->mac));
    } else if (id == WIFI_EVENT_AP_STADISCONNECTED) {
        const wifi_event_ap_stadisconnected_t *e = data;
        ESP_LOGW(TAG, "phone left: " MACSTR, MAC2STR(e->mac));
    }
}

void wifi_ap_start(void)
{
    esp_err_t err = nvs_flash_init(); /* WiFi stores calibration data in NVS */
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap(); /* 192.168.4.1, hands out addresses over DHCP */

    const wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL));

    wifi_config_t config = {
        .ap = {
            .ssid = BELT_WIFI_SSID,
            .ssid_len = strlen(BELT_WIFI_SSID),
            .password = BELT_WIFI_PASSWORD,
            .channel = BELT_WIFI_CHANNEL,
            .max_connection = BELT_WIFI_MAX_CLIENTS,
            .authmode = WIFI_AUTH_WPA2_PSK,
        },
    };
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &config));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE)); /* power saving adds tens of ms of latency */

    ESP_LOGI(TAG, "network \"%s\" up on channel %d, ESP32 at 192.168.4.1:%d", BELT_WIFI_SSID,
             BELT_WIFI_CHANNEL, BELT_UDP_PORT);
}
