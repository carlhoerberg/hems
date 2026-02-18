#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_sleep.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "driver/i2c_master.h"
#include "esp_mac.h"

/* ── Configuration ──────────────────────────────────────────────── */
#define API_URL         "http://webhook.site/2cd9319d-ce88-475d-b3e8-cb9f9d9c7afe"
#define GROUP_TIMEOUT_S 30    /* seconds of no motion before sending batch */
#define PIR_SETTLE_MS   4000  /* wait for PIR to go LOW before sleeping (measured ~3.4s) */

/* ── Pin assignments ────────────────────────────────────────────── */

#define PIN_PIR         GPIO_NUM_4
#define PIN_MODEM_TX    GPIO_NUM_18  /* ESP TX -> Modem RX */
#define PIN_MODEM_RX    GPIO_NUM_17  /* ESP RX <- Modem TX */
#define PIN_MODEM_PWRKEY GPIO_NUM_41
#define PIN_I2C_SDA     GPIO_NUM_15
#define PIN_I2C_SCL     GPIO_NUM_16
#define MAX17048_ADDR   0x36
#define MAX17048_VCELL  0x02
#define I2C_PORT        I2C_NUM_0

/* ── Modem UART ─────────────────────────────────────────────────── */

#define MODEM_UART      UART_NUM_1
#define MODEM_BAUD      115200
#define MODEM_BUF_SIZE  1024
#define AT_TIMEOUT_MS   2000
#define NET_TIMEOUT_MS  60000

/* ── RTC-persistent data ────────────────────────────────────────── */

static RTC_DATA_ATTR uint32_t total_count = 0;   /* lifetime total, persists across deep sleep */
static RTC_DATA_ATTR uint32_t batch_count = 0;   /* current group, reset after send */

static const char *TAG = "trail";
static char device_id[13];  /* 12 hex chars + null */

/* ── Forward declarations ───────────────────────────────────────── */

static void modem_uart_init(void);
static bool modem_power_on(void);
static void modem_power_off(void);
static bool modem_send_at(const char *cmd, const char *expect, int timeout_ms);
static bool modem_wait_network(void);
static void battery_init(void);
static int battery_read_mv(void);
static void battery_deinit(void);
static int modem_read_rssi(void);
static bool modem_http_post(uint32_t total, uint32_t batch, int battery_mv, int rssi);
static void enter_deep_sleep(void);
static void wait_pir_low(void);

/* ── Main ───────────────────────────────────────────────────────── */

void app_main(void)
{
    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    snprintf(device_id, sizeof(device_id), "%02x%02x%02x%02x%02x%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();

    if (cause == ESP_SLEEP_WAKEUP_TIMER) {
        /* Timer expired = no motion for GROUP_TIMEOUT_S, send the batch */
        ESP_LOGI(TAG, "Group timeout, sending batch=%lu total=%lu",
                 (unsigned long)batch_count, (unsigned long)total_count);

        /* Wake MAX17048 early so it has time to settle while modem connects */
        battery_init();

        modem_uart_init();

        bool sent = false;
        for (int attempt = 0; attempt < 2 && !sent; attempt++) {
            if (attempt > 0) {
                ESP_LOGW(TAG, "Retry %d", attempt);
                vTaskDelay(pdMS_TO_TICKS(2000));
            }
            if (modem_power_on() && modem_wait_network() &&
                modem_http_post(total_count, batch_count,
                                battery_read_mv(), modem_read_rssi())) {
                sent = true;
            }
        }
        battery_deinit();

        if (sent) {
            ESP_LOGI(TAG, "POST successful");
        } else {
            ESP_LOGE(TAG, "POST failed, will retry at next send interval");
        }

        modem_power_off();
        batch_count = 0;
    } else {
        /* PIR wakeup (or first boot) = new detection */
        total_count++;
        batch_count++;
        ESP_LOGI(TAG, "Detection! batch=%lu total=%lu",
                 (unsigned long)batch_count, (unsigned long)total_count);
    }

    wait_pir_low();
    enter_deep_sleep();
}

/* ── Deep sleep ─────────────────────────────────────────────────── */

static void enter_deep_sleep(void)
{
    if (batch_count > 0) {
        /* Pending detections: set timer so we send even if no more motion */
        esp_sleep_enable_timer_wakeup((uint64_t)GROUP_TIMEOUT_S * 1000000ULL);
        ESP_LOGI(TAG, "Sleep: PIR + %ds timer, batch=%lu",
                 GROUP_TIMEOUT_S, (unsigned long)batch_count);
    } else {
        /* Nothing pending: wait for PIR only */
        ESP_LOGI(TAG, "Sleep: PIR only, total=%lu", (unsigned long)total_count);
    }
    esp_sleep_enable_ext0_wakeup(PIN_PIR, 1);
    esp_deep_sleep_start();
}

/* ── Wait for PIR to go LOW ─────────────────────────────────────── */

static void wait_pir_low(void)
{
    gpio_config_t pir_conf = {
        .pin_bit_mask = 1ULL << PIN_PIR,
        .mode         = GPIO_MODE_INPUT,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,
    };
    gpio_config(&pir_conf);

    int waited = 0;
    while (gpio_get_level(PIN_PIR) == 1 && waited < PIR_SETTLE_MS) {
        vTaskDelay(pdMS_TO_TICKS(50));
        waited += 50;
    }
}

/* ── Modem UART ─────────────────────────────────────────────────── */

static void modem_uart_init(void)
{
    uart_config_t cfg = {
        .baud_rate  = MODEM_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    uart_driver_install(MODEM_UART, MODEM_BUF_SIZE * 2, 0, 0, NULL, 0);
    uart_param_config(MODEM_UART, &cfg);
    uart_set_pin(MODEM_UART, PIN_MODEM_TX, PIN_MODEM_RX,
                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
}

/* ── AT command helper ──────────────────────────────────────────── */

static bool modem_send_at(const char *cmd, const char *expect, int timeout_ms)
{
    /* Flush any stale data */
    uart_flush_input(MODEM_UART);

    /* Send command */
    char buf[256];
    int len = snprintf(buf, sizeof(buf), "%s\r\n", cmd);
    uart_write_bytes(MODEM_UART, buf, len);
    ESP_LOGI(TAG, "AT> %s", cmd);

    /* Read response */
    int elapsed = 0;
    int pos = 0;
    memset(buf, 0, sizeof(buf));

    while (elapsed < timeout_ms) {
        int n = uart_read_bytes(MODEM_UART, (uint8_t *)buf + pos,
                                sizeof(buf) - pos - 1, pdMS_TO_TICKS(100));
        if (n > 0) {
            pos += n;
            buf[pos] = '\0';
            if (strstr(buf, expect)) {
                ESP_LOGI(TAG, "AT< %s", buf);
                return true;
            }
            if (strstr(buf, "ERROR")) {
                ESP_LOGW(TAG, "AT error: %s", buf);
                return false;
            }
        }
        elapsed += 100;
    }
    ESP_LOGW(TAG, "AT timeout (%s), got: %s", cmd, buf);
    return false;
}

/* ── Modem power control ────────────────────────────────────────── */

static bool modem_power_on(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << PIN_MODEM_PWRKEY,
        .mode         = GPIO_MODE_OUTPUT,
    };
    gpio_config(&io_conf);

    /* PWRKEY pulse: pull low for 1.5s to toggle power */
    gpio_set_level(PIN_MODEM_PWRKEY, 1);
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(PIN_MODEM_PWRKEY, 0);
    vTaskDelay(pdMS_TO_TICKS(1500));
    gpio_set_level(PIN_MODEM_PWRKEY, 1);

    /* Poll AT immediately, 500ms apart, up to 10s total */
    for (int i = 0; i < 20; i++) {
        vTaskDelay(pdMS_TO_TICKS(500));
        if (modem_send_at("AT", "OK", 500)) {
            modem_send_at("ATE0", "OK", 500);
            return true;
        }
    }
    ESP_LOGE(TAG, "Modem not responding");
    return false;
}

static void modem_power_off(void)
{
    modem_send_at("AT+CGACT=0,1", "OK", AT_TIMEOUT_MS);
    modem_send_at("AT+CPOF", "OK", AT_TIMEOUT_MS);
    vTaskDelay(pdMS_TO_TICKS(2000));
}

/* ── Network attach ─────────────────────────────────────────────── */

static bool modem_wait_network(void)
{
    modem_send_at("AT+CFUN=1", "OK", AT_TIMEOUT_MS);

    int elapsed = 0;
    while (elapsed < NET_TIMEOUT_MS) {
        /* Check for EPS Network Registration (4G/LTE): 1=home, 5=roaming */
        if (modem_send_at("AT+CEREG?", "+CEREG: 0,1", 1000) ||
            modem_send_at("AT+CEREG?", "+CEREG: 0,5", 1000)) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(3000));
        elapsed += 4000;
    }

    if (elapsed >= NET_TIMEOUT_MS) {
        ESP_LOGE(TAG, "Network registration timeout");
        return false;
    }

    /* Define and activate PDP context */
    modem_send_at("AT+CGDCONT=1,\"IP\",\"online.telia.se\"", "OK", AT_TIMEOUT_MS);
    return modem_send_at("AT+CGACT=1,1", "OK", 10000);
}

/* ── Battery voltage via MAX17048 I2C ────────────────────────────── */

static i2c_master_bus_handle_t battery_bus = NULL;
static i2c_master_dev_handle_t battery_dev = NULL;

static void battery_init(void)
{
    /* Wake MAX17048 from sleep - it enters sleep when SDA+SCL are low for >2.5s
       (which happens during ESP32 deep sleep). A rising edge on either pin wakes it. */
    gpio_config_t wake_conf = {
        .pin_bit_mask = (1ULL << PIN_I2C_SDA) | (1ULL << PIN_I2C_SCL),
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&wake_conf);
    gpio_set_level(PIN_I2C_SDA, 0);
    gpio_set_level(PIN_I2C_SCL, 0);
    vTaskDelay(pdMS_TO_TICKS(1));
    gpio_set_level(PIN_I2C_SDA, 1);
    gpio_set_level(PIN_I2C_SCL, 1);
    vTaskDelay(pdMS_TO_TICKS(2));
    gpio_reset_pin(PIN_I2C_SDA);
    gpio_reset_pin(PIN_I2C_SCL);

    i2c_master_bus_config_t bus_conf = {
        .i2c_port = I2C_PORT,
        .sda_io_num = PIN_I2C_SDA,
        .scl_io_num = PIN_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .flags.enable_internal_pullup = true,
    };
    if (i2c_new_master_bus(&bus_conf, &battery_bus) != ESP_OK) {
        ESP_LOGW(TAG, "I2C bus init failed");
        battery_bus = NULL;
        return;
    }

    i2c_device_config_t dev_conf = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = MAX17048_ADDR,
        .scl_speed_hz = 100000,
    };
    if (i2c_master_bus_add_device(battery_bus, &dev_conf, &battery_dev) != ESP_OK) {
        ESP_LOGW(TAG, "I2C add device failed");
        i2c_del_master_bus(battery_bus);
        battery_bus = NULL;
        battery_dev = NULL;
    }
}

static int battery_read_mv(void)
{
    if (!battery_dev) return 0;

    uint8_t reg = MAX17048_VCELL;
    uint8_t data[2] = {0};
    esp_err_t err = i2c_master_transmit_receive(battery_dev, &reg, 1, data, 2, 100);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "MAX17048 read failed: %s", esp_err_to_name(err));
        return 0;
    }

    uint16_t raw = (data[0] << 8) | data[1];
    int mv = (int)((raw * 78125ULL) / 1000000ULL);
    ESP_LOGI(TAG, "Battery: %d mV", mv);
    return mv;
}

static void battery_deinit(void)
{
    if (battery_dev) {
        i2c_master_bus_rm_device(battery_dev);
        battery_dev = NULL;
    }
    if (battery_bus) {
        i2c_del_master_bus(battery_bus);
        battery_bus = NULL;
    }
}

/* ── Signal quality via AT+CSQ ───────────────────────────────────── */

static int modem_read_rssi(void)
{
    uart_flush_input(MODEM_UART);

    char cmd[] = "AT+CSQ\r\n";
    uart_write_bytes(MODEM_UART, cmd, strlen(cmd));

    char buf[128] = {0};
    int pos = 0;
    int elapsed = 0;
    while (elapsed < AT_TIMEOUT_MS) {
        int n = uart_read_bytes(MODEM_UART, (uint8_t *)buf + pos,
                                sizeof(buf) - pos - 1, pdMS_TO_TICKS(100));
        if (n > 0) {
            pos += n;
            buf[pos] = '\0';
            /* Response format: +CSQ: <rssi>,<ber> */
            char *p = strstr(buf, "+CSQ:");
            if (p) {
                int rssi, ber;
                if (sscanf(p, "+CSQ: %d,%d", &rssi, &ber) >= 1) {
                    int dbm = (rssi == 99) ? 0 : (rssi * 2) - 113;
                    ESP_LOGI(TAG, "RSSI: %d (CSQ %d)", dbm, rssi);
                    return dbm;
                }
            }
        }
        elapsed += 100;
    }
    ESP_LOGW(TAG, "Could not read signal quality");
    return 99;
}

/* ── HTTP POST ──────────────────────────────────────────────────── */

static bool modem_http_post(uint32_t total, uint32_t batch, int battery_mv, int rssi)
{
    /* Build JSON payload */
    char payload[160];
    snprintf(payload, sizeof(payload),
             "{\"device_id\":\"%s\",\"total\":%lu,\"batch\":%lu,\"battery_mv\":%d,\"rssi_dbm\":%d}",
             device_id, (unsigned long)total, (unsigned long)batch, battery_mv, rssi);

    /* Initialize HTTP service */
    if (!modem_send_at("AT+HTTPINIT", "OK", AT_TIMEOUT_MS)) {
        return false;
    }

    /* Set URL */
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "AT+HTTPPARA=\"URL\",\"%s\"", API_URL);
    if (!modem_send_at(cmd, "OK", AT_TIMEOUT_MS)) {
        goto cleanup;
    }

    /* Set content type */
    if (!modem_send_at("AT+HTTPPARA=\"CONTENT\",\"application/json\"", "OK", AT_TIMEOUT_MS)) {
        goto cleanup;
    }

    /* Send HTTPDATA: tell modem how many bytes and timeout */
    snprintf(cmd, sizeof(cmd), "AT+HTTPDATA=%d,5000", (int)strlen(payload));
    if (!modem_send_at(cmd, "DOWNLOAD", AT_TIMEOUT_MS)) {
        goto cleanup;
    }

    /* Write payload */
    uart_write_bytes(MODEM_UART, payload, strlen(payload));
    vTaskDelay(pdMS_TO_TICKS(1000));

    /* Execute POST (method 1 = POST) */
    if (!modem_send_at("AT+HTTPACTION=1", "+HTTPACTION:", 15000)) {
        goto cleanup;
    }

    modem_send_at("AT+HTTPTERM", "OK", AT_TIMEOUT_MS);
    return true;

cleanup:
    modem_send_at("AT+HTTPTERM", "OK", AT_TIMEOUT_MS);
    return false;
}
