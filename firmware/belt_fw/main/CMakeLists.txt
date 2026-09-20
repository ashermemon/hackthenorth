idf_component_register(SRCS "belt_fw.c" "belt_protocol.c" "motors.c" "wifi_ap.c"
                       INCLUDE_DIRS "."
                       REQUIRES driver esp_timer esp_wifi esp_netif esp_event nvs_flash lwip)
