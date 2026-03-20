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
    uint64_t center_freq_hz;
    uint32_t rbw_hz;
    uint32_t fft_size;
} g_spectrum_params;

/* IQ capture parameters for thread */
static struct {
    uint64_t center_freq_hz;
    uint32_t rbw_hz;
    uint32_t iq_byte_size;
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
 * Set center frequency (in Hz)
 */
static int set_center_frequency(uint64_t freq_hz)
{
    char cmd[128];

    /* Validate frequency range: 60MHz to 6GHz */
    if (freq_hz < 60000000ULL || freq_hz > 6000000000ULL) {
    	printf("[TEST_6144] Invalid frequency: %llu Hz (valid: 60000000-6000000000)\n", freq_hz);
        return -1;
    }

    /* Set RX LO frequency */
    sprintf(cmd, "echo %llu > /sys/bus/iio/devices/iio:device0/out_altvoltage0_RX_LO_frequency", freq_hz);
    system(cmd);

    printf("[TEST_6144] Set center frequency: %llu Hz\n", freq_hz);

    return 0;
}

/*
 * Convert RBW Hz to index
 */
static int rbw_hz_to_index(uint32_t rbw_hz)
{
    switch (rbw_hz) {
        case 15000:  return 0;
        case 30000:  return 1;
        case 60000:  return 2;
        case 120000: return 3;
        default:     return 2;  /* Default to 60kHz */
    }
}

/*
 * Spectrum measurement thread
 */
static void* spectrum_thread_func(void* arg)
{
    char resp_msg[128];
    int32_t* spectrum_data = NULL;
    uint32_t fft_size = g_spectrum_params.fft_size;

    printf("[TEST_6144] Spectrum thread started\n");

    /* Allocate spectrum data buffer (fft_size points * 4 bytes) */
    spectrum_data = (int32_t*)malloc(fft_size * sizeof(int32_t));
    if (!spectrum_data) {
    	printf("[TEST_6144] Failed to allocate spectrum buffer\n");
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        g_state.running = 0;
        return NULL;
    }

    /* Set center frequency (now in Hz) */
    if (set_center_frequency(g_spectrum_params.center_freq_hz) < 0) {
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        free(spectrum_data);
        g_state.running = 0;
        return NULL;
    }

    g_state.current_freq = g_spectrum_params.center_freq_hz / 1000;  /* Store as kHz internally */
    g_state.current_rbw = rbw_hz_to_index(g_spectrum_params.rbw_hz);

    /* Configure FPGA for spectrum capture */
    PL_CTRL_Write(SA_EN, 1);
    PL_CTRL_Write(SA_CAPT_MODE, 1);  /* General mode */

    /* Set FFT size in FPGA */
    PL_CTRL_Write(COUNTER1_PERIOD, fft_size);

    /* Allow settling time */
    usleep(10000);

    /* Trigger capture */
    PL_CTRL_Write(SA_MEASURE_START, 1);
    usleep(1000);
    PL_CTRL_Write(SA_MEASURE_START, 0);

    /* Wait for capture complete */
    usleep(50000);  /* 50ms for 61.44MHz capture */

    /* Read spectrum data from DRAM */
    int32_t* dram_buffer = (int32_t*)get_DRAM_buffer();
    if (dram_buffer) {
        memcpy(spectrum_data, dram_buffer, fft_size * sizeof(int32_t));
    }

    /* Send response header */
    /* Format: 0x45 0x01 <status> */
    sprintf(resp_msg, "%s %02x OK", CMD_61_44_TEST_RESP, TYPE_61_44_SPECTRUM);
    pubMqttString(resp_msg, strlen(resp_msg));

    /* Send spectrum data as binary */
    pubMqttDataByteArray(spectrum_data, fft_size * sizeof(int32_t));

    printf("[TEST_6144] Spectrum data sent: freq=%llu Hz, rbw=%u Hz, fft_size=%u\n",
           g_spectrum_params.center_freq_hz, g_spectrum_params.rbw_hz, fft_size);

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
    int8_t* iq_data = NULL;
    uint32_t iq_byte_size = g_iq_params.iq_byte_size;

    printf("[TEST_6144] IQ capture thread started\n");

    /* Limit byte size (max samples * 4 bytes per I/Q pair) */
    if (iq_byte_size > TEST_6144_MAX_IQ_SAMPLES * 4) {
        iq_byte_size = TEST_6144_MAX_IQ_SAMPLES * 4;
    }

    /* Allocate IQ data buffer */
    iq_data = (int8_t*)malloc(iq_byte_size);
    if (!iq_data) {
    	printf("[TEST_6144] Failed to allocate IQ buffer\n");
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        g_state.running = 0;
        return NULL;
    }

    /* Set center frequency (now in Hz) */
    if (set_center_frequency(g_iq_params.center_freq_hz) < 0) {
        sprintf(resp_msg, "%s %02x %d", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE, TEST_6144_STATUS_ERROR);
        pubMqttString(resp_msg, strlen(resp_msg));
        free(iq_data);
        g_state.running = 0;
        return NULL;
    }

    g_state.current_freq = g_iq_params.center_freq_hz / 1000;  /* Store as kHz internally */
    g_state.current_rbw = rbw_hz_to_index(g_iq_params.rbw_hz);

    /* Configure for IQ capture mode */
    PL_CTRL_Write(SA_EN, 1);
    PL_CTRL_Write(SA_CAPT_MODE, 0);  /* IQ capture mode */

    /* Set sample count in FPGA (byte_size / 4 = number of I/Q pairs) */
    uint32_t sample_count = iq_byte_size / 4;
    PL_CTRL_Write(COUNTER1_PERIOD, sample_count);

    usleep(10000);

    /* Trigger capture */
    PL_CTRL_Write(SA_MEASURE_START, 1);
    usleep(1000);
    PL_CTRL_Write(SA_MEASURE_START, 0);

    /* Wait for capture (samples / sample_rate * 1000000 us + margin) */
    uint32_t capture_time_us = (sample_count * 1000000ULL / TEST_6144_SAMPLE_RATE) + 10000;
    usleep(capture_time_us);

    /* Read IQ data from DRAM */
    int8_t* dram_buffer = (int8_t*)get_DRAM_buffer();
    if (dram_buffer) {
        memcpy(iq_data, dram_buffer, iq_byte_size);
    }

    /* Send response header */
    /* Format: 0x45 0x02 OK */
    sprintf(resp_msg, "%s %02x OK", CMD_61_44_TEST_RESP, TYPE_61_44_IQ_CAPTURE);
    pubMqttString(resp_msg, strlen(resp_msg));

    /* Send IQ data */
    pubMqttDataByteArray((int*)iq_data, iq_byte_size);

    printf("[TEST_6144] IQ data sent: freq=%llu Hz, rbw=%u Hz, bytes=%u\n",
           g_iq_params.center_freq_hz, g_iq_params.rbw_hz, iq_byte_size);

    free(iq_data);
    g_state.running = 0;
    g_thread_running = 0;

    printf("[TEST_6144] IQ capture thread ended\n");

    return NULL;
}

/*
 * Start spectrum measurement
 */
int test_6144_spectrum_start(uint64_t center_freq_hz, uint32_t rbw_hz, uint32_t fft_size)
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

    /* Validate and default RBW */
    if (rbw_hz != 15000 && rbw_hz != 30000 && rbw_hz != 60000 && rbw_hz != 120000) {
        rbw_hz = 60000;  /* Default to 60kHz */
    }

    /* Validate FFT size */
    if (fft_size == 0 || fft_size > TEST_6144_MAX_IQ_SAMPLES) {
        fft_size = TEST_6144_SPECTRUM_POINTS;  /* Default to 8192 */
    }

    /* Store parameters for thread */
    g_spectrum_params.center_freq_hz = center_freq_hz;
    g_spectrum_params.rbw_hz = rbw_hz;
    g_spectrum_params.fft_size = fft_size;

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

    printf("[TEST_6144] Spectrum measurement started: freq=%llu Hz, rbw=%u Hz, fft_size=%u\n",
               center_freq_hz, rbw_hz, fft_size);

    return 0;
}

/*
 * Start IQ data capture
 */
int test_6144_iq_capture_start(uint64_t center_freq_hz, uint32_t rbw_hz, uint32_t iq_byte_size)
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

    /* Validate and default RBW */
    if (rbw_hz != 15000 && rbw_hz != 30000 && rbw_hz != 60000 && rbw_hz != 120000) {
        rbw_hz = 60000;  /* Default to 60kHz */
    }

    /* Validate byte size */
    if (iq_byte_size == 0 || iq_byte_size > TEST_6144_MAX_IQ_SAMPLES * 4) {
        iq_byte_size = 8192 * 4;  /* Default to 8192 samples * 4 bytes */
    }

    /* Store parameters for thread */
    g_iq_params.center_freq_hz = center_freq_hz;
    g_iq_params.rbw_hz = rbw_hz;
    g_iq_params.iq_byte_size = iq_byte_size;

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

    printf("[TEST_6144] IQ capture started: freq=%llu Hz, rbw=%u Hz, bytes=%u\n",
               center_freq_hz, rbw_hz, iq_byte_size);

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
 *   0x44 0x00                                       - Initialize
 *   0x44 0x01 <freq_hz> <rbw_hz> <fft_size>        - Spectrum/FFT
 *   0x44 0x02 <freq_hz> <rbw_hz> <iq_byte_size>    - IQ capture
 *   0x44 0x0F                                       - Stop
 */
int test_6144_mqtt_handler(const char* mesg)
{
    uint32_t cmd_mode = 0;
    uint32_t test_type = 0;
    uint64_t center_freq_hz = 2000000000ULL;  /* Default 2GHz in Hz */
    uint32_t rbw_hz = 60000;                   /* Default 60kHz */
    uint32_t param3 = 0;
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
            /* 0x44 0x01 <freq_hz> <rbw_hz> <fft_size> */
            scanned = sscanf(mesg, "%x %x %llu %u %u", &cmd_mode, &test_type,
                           &center_freq_hz, &rbw_hz, &param3);
            if (scanned < 3) {
                center_freq_hz = 2000000000ULL;  /* Default 2GHz */
            }
            if (scanned < 4) {
                rbw_hz = 60000;  /* Default 60kHz */
            }
            if (scanned < 5) {
                param3 = TEST_6144_SPECTRUM_POINTS;  /* Default FFT size */
            }
            return test_6144_spectrum_start(center_freq_hz, rbw_hz, param3);

        case TYPE_61_44_IQ_CAPTURE:
            /* 0x44 0x02 <freq_hz> <rbw_hz> <iq_byte_size> */
            scanned = sscanf(mesg, "%x %x %llu %u %u", &cmd_mode, &test_type,
                           &center_freq_hz, &rbw_hz, &param3);
            if (scanned < 3) {
                center_freq_hz = 2000000000ULL;  /* Default 2GHz */
            }
            if (scanned < 4) {
                rbw_hz = 60000;  /* Default 60kHz */
            }
            if (scanned < 5) {
                param3 = 8192 * 4;  /* Default: 8192 samples * 4 bytes */
            }
            return test_6144_iq_capture_start(center_freq_hz, rbw_hz, param3);

        case TYPE_61_44_STOP:
            /* 0x44 0x0F */
            test_6144_stop();
            return 0;

        default:
        	printf("[TEST_6144] Unknown test type: 0x%02x\n", test_type);
            return -1;
    }
}
