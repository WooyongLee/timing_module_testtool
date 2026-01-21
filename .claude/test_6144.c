/*
 * test_6144.c
 *
 * 61.44MHz AD9361 Clock Test Protocol Handler
 * For Timing Module Phase 1 verification
 *
 * Supports:
 * - Spectrum measurement with 8192 points at 61.44MHz sampling rate
 * - IQ data capture for raw signal analysis
 */

#include "test_6144.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

#include <command/command.h>
#include <command/MQTT/mqtt_mgmt.h>
#include <HW/ad9361/ad9361_manager.h>
#include <HW/PL/pl_regs.h>
#include <HW/PL/spi.h>
#include <HW/hw_mgmt.h>

#define MODULE_NAME "TEST_6144"
#include <common/debug.h>


/* Static state */
static Test6144_State g_state = {0};
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

/* RBW values in Hz */
static const uint32_t rbw_table[] = {
    15000,   /* 0: 15 kHz */
    30000,   /* 1: 30 kHz */
    60000,   /* 2: 60 kHz */
    120000   /* 3: 120 kHz */
};

/* Forward declarations */
static void* spectrum_thread_func(void* arg);
static void* iq_capture_thread_func(void* arg);

/* Thread handles */
static pthread_t g_spectrum_thread;
static pthread_t g_iq_thread;
static volatile int g_thread_running = 0;

/* Spectrum parameters for thread */
static struct {
    uint64_t center_freq_khz;
    uint32_t rbw_idx;
    uint32_t maxhold;
} g_spectrum_params;

/* IQ capture parameters for thread */
static struct {
    uint64_t center_freq_khz;
    uint32_t sample_count;
} g_iq_params;

/*
 * Initialize 61.44MHz test mode
 */
int test_6144_init(void)
{
    char resp_msg[64];

    pthread_mutex_lock(&g_mutex);

    if (g_state.initialized) {
        printf("[TEST_6144] Already initialized\n");
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_INIT, TEST_6144_STATUS_OK);
        pubMqttString(resp_msg, strlen(resp_msg));
        return 0;
    }

    printf("[TEST_6144] Initializing 61.44MHz test mode...\n");

    /* Initialize AD9361 with meas_type = 8 (61.44MHz mode) */
    init_ad9361_module(8);

    g_state.initialized = 1;
    g_state.running = 0;
    g_state.current_freq = 0;
    g_state.current_rbw = TEST_6144_DEFAULT_RBW_IDX;

    pthread_mutex_unlock(&g_mutex);

    printf("[TEST_6144] Initialization complete\n");

    /* Send response */
    sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_INIT, TEST_6144_STATUS_OK);
    pubMqttString(resp_msg, strlen(resp_msg));

    return 0;
}

/*
 * Deinitialize 61.44MHz test mode
 */
void test_6144_deinit(void)
{
    pthread_mutex_lock(&g_mutex);

    if (g_state.running) {
        g_thread_running = 0;
        pthread_mutex_unlock(&g_mutex);
        test_6144_stop();
        pthread_mutex_lock(&g_mutex);
    }

    g_state.initialized = 0;
    g_state.running = 0;

    pthread_mutex_unlock(&g_mutex);

    printf("[TEST_6144] Deinitialized\n");
}

/*
 * Set center frequency
 */
static int set_center_frequency(uint64_t freq_khz)
{
    char cmd[128];
    uint64_t freq_hz = freq_khz * 1000ULL;

    /* Validate frequency range: 60MHz to 6GHz */
    if (freq_khz < 60000 || freq_khz > 6000000) {
    	printf("[TEST_6144] Invalid frequency: %llu kHz (valid: 60000-6000000)\n", freq_khz);
        return -1;
    }

    /* Set RX LO frequency */
    sprintf(cmd, "echo %llu > /sys/bus/iio/devices/iio:device0/out_altvoltage0_RX_LO_frequency", freq_hz);
    system(cmd);

    printf("[TEST_6144] Set center frequency: %llu kHz (%llu Hz)\n", freq_khz, freq_hz);

    return 0;
}

/*
 * Spectrum measurement thread
 */
static void* spectrum_thread_func(void* arg)
{
    char resp_msg[128];
    int32_t* spectrum_data = NULL;
    int i;

    printf("[TEST_6144] Spectrum thread started\n");

    /* Allocate spectrum data buffer (8192 points * 4 bytes) */
    spectrum_data = (int32_t*)malloc(TEST_6144_SPECTRUM_POINTS * sizeof(int32_t));
    if (!spectrum_data) {
    	printf("[TEST_6144] Failed to allocate spectrum buffer\n");
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        g_state.running = 0;
        return NULL;
    }

    /* Set center frequency */
    if (set_center_frequency(g_spectrum_params.center_freq_khz) < 0) {
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        free(spectrum_data);
        g_state.running = 0;
        return NULL;
    }

    g_state.current_freq = g_spectrum_params.center_freq_khz;
    g_state.current_rbw = g_spectrum_params.rbw_idx;

    /* Configure FPGA for spectrum capture */
    PL_CTRL_Write(SA_EN, 1);
    PL_CTRL_Write(SA_CAPT_MODE, 1);  /* General mode */

    /* Allow settling time */
    usleep(10000);

    while (g_thread_running) {
        /* Trigger capture */
        PL_CTRL_Write(SA_MEASURE_START, 1);
        usleep(1000);
        PL_CTRL_Write(SA_MEASURE_START, 0);

        /* Wait for capture complete */
        usleep(50000);  /* 50ms for 61.44MHz capture */

        /* Read spectrum data from DRAM */
        int32_t* dram_buffer = (int32_t*)get_DRAM_buffer();
        if (dram_buffer) {
            memcpy(spectrum_data, dram_buffer, TEST_6144_SPECTRUM_POINTS * sizeof(int32_t));
        }

        /* Apply maxhold if enabled */
        /* (maxhold logic can be added here if needed) */

        /* Send data via MQTT */
        /* Format: 0x45 0x01 <status> followed by binary data */
        sprintf(resp_msg, "%s %02x %d %llu %u",
                CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_OK,
                g_spectrum_params.center_freq_khz, TEST_6144_SPECTRUM_POINTS);
        pubMqttString(resp_msg, strlen(resp_msg));

        /* Send spectrum data as int array */
        pubMqttDataByteArray(spectrum_data, TEST_6144_SPECTRUM_POINTS * sizeof(int32_t));

        /* For single shot, break after first capture */
        if (!g_spectrum_params.maxhold) {
            break;
        }

        usleep(100000);  /* 100ms between captures in maxhold mode */
    }

    free(spectrum_data);
    g_state.running = 0;
    g_thread_running = 0;

    printf("[TEST_6144] Spectrum thread ended\n");

    return NULL;
}

/*
 * IQ capture thread
 */
static void* iq_capture_thread_func(void* arg)
{
    char resp_msg[128];
    int16_t* iq_data = NULL;
    uint32_t actual_samples;

    printf("[TEST_6144] IQ capture thread started\n");

    /* Limit sample count */
    actual_samples = g_iq_params.sample_count;
    if (actual_samples > TEST_6144_MAX_IQ_SAMPLES) {
        actual_samples = TEST_6144_MAX_IQ_SAMPLES;
    }

    /* Allocate IQ data buffer (I + Q = 2 * samples * 2 bytes) */
    iq_data = (int16_t*)malloc(actual_samples * 2 * sizeof(int16_t));
    if (!iq_data) {
    	printf("[TEST_6144] Failed to allocate IQ buffer\n");
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        g_state.running = 0;
        return NULL;
    }

    /* Set center frequency */
    if (set_center_frequency(g_iq_params.center_freq_khz) < 0) {
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        free(iq_data);
        g_state.running = 0;
        return NULL;
    }

    g_state.current_freq = g_iq_params.center_freq_khz;

    /* Configure for IQ capture mode */
    PL_CTRL_Write(SA_EN, 1);
    PL_CTRL_Write(SA_CAPT_MODE, 0);  /* IQ capture mode */

    /* Set sample count in FPGA */
    PL_CTRL_Write(COUNTER1_PERIOD, actual_samples);

    usleep(10000);

    /* Trigger capture */
    PL_CTRL_Write(SA_MEASURE_START, 1);
    usleep(1000);
    PL_CTRL_Write(SA_MEASURE_START, 0);

    /* Wait for capture (samples / sample_rate * 1000000 us + margin) */
    uint32_t capture_time_us = (actual_samples * 1000000ULL / TEST_6144_SAMPLE_RATE) + 10000;
    usleep(capture_time_us);

    /* Read IQ data from DRAM */
    int16_t* dram_buffer = (int16_t*)get_DRAM_buffer();
    if (dram_buffer) {
        memcpy(iq_data, dram_buffer, actual_samples * 2 * sizeof(int16_t));
    }

    /* Send response header */
    sprintf(resp_msg, "%s %02x %d %llu %u",
            CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_OK,
            g_iq_params.center_freq_khz, actual_samples);
    pubMqttString(resp_msg, strlen(resp_msg));

    /* Send IQ data */
    pubMqttDataByteArray((int*)iq_data, actual_samples * 2 * sizeof(int16_t));

    free(iq_data);
    g_state.running = 0;
    g_thread_running = 0;

    printf("[TEST_6144] IQ capture thread ended\n");

    return NULL;
}

/*
 * Start spectrum measurement
 */
int test_6144_spectrum_start(uint64_t center_freq_khz, uint32_t rbw_idx, uint32_t maxhold)
{
    char resp_msg[64];

    pthread_mutex_lock(&g_mutex);

    if (!g_state.initialized) {
    	printf("[TEST_6144] Not initialized\n");
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_NOT_INIT);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -1;
    }

    if (g_state.running) {
    	printf("[TEST_6144] Already running\n");
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_BUSY);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -2;
    }

    /* Validate RBW index */
    if (rbw_idx > 3) {
        rbw_idx = TEST_6144_DEFAULT_RBW_IDX;
    }

    /* Store parameters for thread */
    g_spectrum_params.center_freq_khz = center_freq_khz;
    g_spectrum_params.rbw_idx = rbw_idx;
    g_spectrum_params.maxhold = maxhold;

    g_state.running = 1;
    g_thread_running = 1;

    pthread_mutex_unlock(&g_mutex);

    /* Start spectrum thread */
    int rc = pthread_create(&g_spectrum_thread, NULL, spectrum_thread_func, NULL);
    if (rc) {
    	printf("[TEST_6144] Failed to create spectrum thread: %d\n", rc);
        g_state.running = 0;
        g_thread_running = 0;
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -3;
    }

    printf("[TEST_6144] Spectrum measurement started: freq=%llu kHz, rbw=%u, maxhold=%u\n",
               center_freq_khz, rbw_idx, maxhold);

    return 0;
}

/*
 * Start IQ data capture
 */
int test_6144_iq_capture_start(uint64_t center_freq_khz, uint32_t sample_count)
{
    char resp_msg[64];

    pthread_mutex_lock(&g_mutex);

    if (!g_state.initialized) {
    	printf("[TEST_6144] Not initialized\n");
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_NOT_INIT);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -1;
    }

    if (g_state.running) {
    	printf("[TEST_6144] Already running\n");
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_BUSY);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -2;
    }

    /* Store parameters for thread */
    g_iq_params.center_freq_khz = center_freq_khz;
    g_iq_params.sample_count = sample_count;

    g_state.running = 1;
    g_thread_running = 1;

    pthread_mutex_unlock(&g_mutex);

    /* Start IQ capture thread */
    int rc = pthread_create(&g_iq_thread, NULL, iq_capture_thread_func, NULL);
    if (rc) {
    	printf("[TEST_6144] Failed to create IQ capture thread: %d\n", rc);
        g_state.running = 0;
        g_thread_running = 0;
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        return -3;
    }

    printf("[TEST_6144] IQ capture started: freq=%llu kHz, samples=%u\n",
               center_freq_khz, sample_count);

    return 0;
}

/*
 * Stop current measurement
 */
void test_6144_stop(void)
{
    char resp_msg[64];

    pthread_mutex_lock(&g_mutex);

    if (!g_state.running) {
        pthread_mutex_unlock(&g_mutex);
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_STOP, TEST_6144_STATUS_OK);
        pubMqttString(resp_msg, strlen(resp_msg));
        return;
    }

    g_thread_running = 0;

    pthread_mutex_unlock(&g_mutex);

    /* Wait for thread to finish */
    usleep(200000);

    printf("[TEST_6144] Measurement stopped\n");

    sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_STOP, TEST_6144_STATUS_OK);
    pubMqttString(resp_msg, strlen(resp_msg));
}

/*
 * Check if measurement is running
 */
int test_6144_is_running(void)
{
    return g_state.running;
}

/*
 * Get current state
 */
Test6144_State* test_6144_get_state(void)
{
    return &g_state;
}

/*
 * MQTT command handler
 * Protocol format:
 *   0x44 0x00                                      - Initialize
 *   0x44 0x01 <center_freq_khz> <rbw_idx> <maxhold> - Spectrum
 *   0x44 0x02 <center_freq_khz> <sample_count>     - IQ capture
 *   0x44 0x0F                                      - Stop
 */
int test_6144_mqtt_handler(const char* mesg)
{
    uint32_t cmd_mode = 0;
    uint32_t test_type = 0;
    uint64_t center_freq_khz = 2000000;  /* Default 2GHz */
    uint32_t param1 = 0;
    uint32_t param2 = 0;
    int scanned;

    /* Parse command type */
    scanned = sscanf(mesg, "%x %x", &cmd_mode, &test_type);
    if (scanned < 2) {
    	printf("[TEST_6144] Invalid command format\n");
        return -1;
    }

    printf("[TEST_6144] Received: cmd=0x%02x type=0x%02x mesg=%s\n", cmd_mode, test_type, mesg);

    switch (test_type) {
        case TYPE_61_44_INIT:
            /* 0x44 0x00 */
            return test_6144_init();

        case TYPE_61_44_SPECTRUM:
            /* 0x44 0x01 <center_freq_khz> <rbw_idx> <maxhold> */
            scanned = sscanf(mesg, "%x %x %llu %u %u", &cmd_mode, &test_type,
                           &center_freq_khz, &param1, &param2);
            if (scanned < 3) {
                center_freq_khz = 2000000;  /* Default 2GHz */
            }
            if (scanned < 4) {
                param1 = TEST_6144_DEFAULT_RBW_IDX;  /* Default RBW */
            }
            if (scanned < 5) {
                param2 = 0;  /* MaxHold off */
            }
            return test_6144_spectrum_start(center_freq_khz, param1, param2);

        case TYPE_61_44_IQ_CAPTURE:
            /* 0x44 0x02 <center_freq_khz> <sample_count> */
            scanned = sscanf(mesg, "%x %x %llu %u", &cmd_mode, &test_type,
                           &center_freq_khz, &param1);
            if (scanned < 3) {
                center_freq_khz = 2000000;  /* Default 2GHz */
            }
            if (scanned < 4) {
                param1 = 8192;  /* Default sample count */
            }
            return test_6144_iq_capture_start(center_freq_khz, param1);

        case TYPE_61_44_STOP:
            /* 0x44 0x0F */
            test_6144_stop();
            return 0;

        default:
        	printf("[TEST_6144] Unknown test type: 0x%02x\n", test_type);
            return -1;
    }
}
