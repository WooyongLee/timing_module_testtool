/*
 * test_6144.h
 *
 * 61.44MHz AD9361 Clock Test Protocol Handler
 * For Timing Module Phase 1 verification
 *
 * Protocol Format:
 *   0x44 0x00                           - Initialize 61.44MHz mode
 *   0x44 0x01 <center_freq_khz> <rbw_idx> <maxhold> - Spectrum measurement
 *   0x44 0x02 <center_freq_khz> <sample_count>      - IQ data capture
 *   0x44 0x0F                           - Stop measurement
 *
 * Response Format:
 *   0x45 <type> <status> [data...]
 */

#ifndef SRC_COMMAND_TEST_6144_H_
#define SRC_COMMAND_TEST_6144_H_

#include <stdint.h>

/* Configuration Constants */
#define TEST_6144_SAMPLE_RATE       61440000    /* 61.44 MHz */
#define TEST_6144_SPECTRUM_POINTS   8192        /* Spectrum data points */
#define TEST_6144_DEFAULT_RBW_IDX   2           /* Default: 60kHz */
#define TEST_6144_MAX_IQ_SAMPLES    65536       /* Max IQ samples per capture */

/* RBW Index to Hz mapping */
#define TEST_6144_RBW_15K   0   /* 15 kHz */
#define TEST_6144_RBW_30K   1   /* 30 kHz */
#define TEST_6144_RBW_60K   2   /* 60 kHz */
#define TEST_6144_RBW_120K  3   /* 120 kHz */

/* Status codes */
#define TEST_6144_STATUS_OK         0
#define TEST_6144_STATUS_ERROR      1
#define TEST_6144_STATUS_BUSY       2
#define TEST_6144_STATUS_NOT_INIT   3

/* Command structure for 61.44MHz test */
typedef struct {
    uint32_t type;              /* Measurement type (0x00, 0x01, 0x02, 0x0F) */
    uint64_t center_freq_khz;   /* Center frequency in kHz */
    uint32_t rbw_idx;           /* RBW index (0-3) */
    uint32_t maxhold;           /* Max hold mode (0=off, 1=on) */
    uint32_t sample_count;      /* IQ sample count */
} Test6144_Cmd;

/* State structure */
typedef struct {
    int initialized;            /* Mode initialized flag */
    int running;                /* Measurement running flag */
    uint64_t current_freq;      /* Current center frequency */
    uint32_t current_rbw;       /* Current RBW setting */
} Test6144_State;

/* Public functions */

/**
 * Initialize 61.44MHz test mode
 * Configures AD9361 with SA_50M_Filter.ftr and sets sampling rate
 * @return 0 on success, negative on error
 */
int test_6144_init(void);

/**
 * Deinitialize 61.44MHz test mode
 */
void test_6144_deinit(void);

/**
 * Start spectrum measurement
 * @param center_freq_khz Center frequency in kHz (60000 - 6000000)
 * @param rbw_idx RBW index (0=15kHz, 1=30kHz, 2=60kHz, 3=120kHz)
 * @param maxhold Max hold mode (0=off, 1=on)
 * @return 0 on success, negative on error
 */
int test_6144_spectrum_start(uint64_t center_freq_khz, uint32_t rbw_idx, uint32_t maxhold);

/**
 * Start IQ data capture
 * @param center_freq_khz Center frequency in kHz
 * @param sample_count Number of IQ samples to capture
 * @return 0 on success, negative on error
 */
int test_6144_iq_capture_start(uint64_t center_freq_khz, uint32_t sample_count);

/**
 * Stop current measurement
 */
void test_6144_stop(void);

/**
 * Check if measurement is running
 * @return 1 if running, 0 otherwise
 */
int test_6144_is_running(void);

/**
 * Get current state
 * @return pointer to state structure
 */
Test6144_State* test_6144_get_state(void);

/**
 * MQTT command handler for 61.44MHz test
 * Called from mqtt_mgmt.c when CMD_61_44_TEST (0x44) is received
 * @param mesg Raw MQTT message string
 * @return 0 on success, negative on error
 */
int test_6144_mqtt_handler(const char* mesg);

#endif /* SRC_COMMAND_TEST_6144_H_ */
