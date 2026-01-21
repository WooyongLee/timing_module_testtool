/*
 * command.h
 *
 *  Created on: Feb 11, 2019
 *      Author: codeart
 */

#ifndef SRC_COMMAND_COMMAND_H_
#define SRC_COMMAND_COMMAND_H_

#include <stdio.h>
#include <stdint.h>

// Project Specific
#include <common/config.h>

#define GATE_SYMB

#define NR_NEW_FEATURE

typedef enum {
    NONE = -1,
#if MQTT_ENABLED
    MQTT =  0,
#endif
#if UART_ENABLED
    UART,
#endif
    TypeCount,
} ProtocolType;

typedef void (*commandHandler)(void*);
//typedef void (*measuredDataHandler)(void* , void*);

typedef struct {
    ProtocolType type;
    uint32_t code;
    uint64_t arg_uint[8];
    int32_t  arg_int[4];
    commandHandler handler;
} Command;

typedef struct {
    ProtocolType type;
    uint32_t code; // Measurement mode
    uint8_t meas_mode;
    uint8_t meas_type;
    uint8_t data_point;
    // Freq/Dist
    uint64_t start_freq;
    uint64_t stop_freq;
    uint32_t distance;
    // DTF
    uint32_t cable_loss;
    uint32_t prop_velocity;
    uint8_t windowing;
    // Calibration
    uint8_t cal_step;
    uint8_t cal_type;
    uint8_t user_cal_use;
    // General purpose
    uint32_t gp[3];

    commandHandler handler;
} CommandVSWR;

typedef struct {
    ProtocolType type;
    uint32_t code; // Measurement mode
    uint32_t arg1;
    uint32_t arg2;
    uint32_t arg3;

    commandHandler handler;
} CommandMISC;

typedef struct {
    int32_t type;
    uint16_t code; // Measurement mode
    uint16_t meas_mode;
    uint16_t meas_type;
    uint16_t data_point;
    // Frequency
    uint64_t center_freq;
    uint64_t span;
    // BW
    uint16_t rbw;
    uint16_t vbw;
    // Amplitude
    uint16_t amp_mode;
    uint16_t amp_atten;
    uint16_t amp_preamp;
    int16_t amp_offset;
    // Trace
    uint16_t trace1_mode;
    uint16_t trace1_type;
    uint16_t trace1_detector;
    uint16_t trace2_mode;
	uint16_t trace2_type;
	uint16_t trace2_detector;
	uint16_t trace3_mode;
	uint16_t trace3_type;
	uint16_t trace3_detector;
	uint16_t trace4_mode;
	uint16_t trace4_type;
	uint16_t trace4_detector;
	// Sweep Time
	uint16_t sweep_time_mode;
	uint32_t sweep_time;
	uint16_t gate_mode;
	uint16_t gate_view;
	uint32_t gate_view_sweep_time;
	uint32_t gate_delay;
	uint32_t gate_length;
	uint32_t gate_source;
	// JBK : 20210713 =>
	// Add New gate param
	uint16_t gate_num;
	uint16_t gate_type;
	uint32_t gate_delta;
	// JBK : 20210713 <=
    /* Ryan Add , to support number of gate */
#ifndef GATE_SYMB
    uint16_t gate_delay_slot;
    uint16_t gate_delay_symbol;
    uint16_t gate_length_slot;
    uint16_t gate_length_symbol;
#endif
    /* Ryan Add */

	// Different Individual
	// Measure Setup (Swept SA / Channel Power / Occupied BW)
	uint16_t avg_hold_mode;
	uint16_t avg_number;
    uint16_t obw_power;
    int16_t xdb;
    uint32_t integration_bw;

    // Measure Setup (ACLR)
//    uint8_t aclr_avg_hold_mode;
//    uint8_t aclr_avg_number;
    // Measure Setup (ACLR) -> Carrier Setup
    uint16_t aclr_Carriers;
    uint16_t aclr_Ref_Carriers;
    uint32_t aclr_Carrier_Sapcing;
    uint32_t aclr_Integ_BW;
    // Measure Setup (ACLR) -> Offset
    uint16_t aclr_Number_of_Offset;
    uint32_t aclr_Offset_Spacing[5];
    uint32_t aclr_Offset_Integ_BW[5];
    uint32_t aclr_Offset_Side[5];
    uint32_t aclr_Fail_Source[5];
    int32_t aclr_Abs_Limit[5];
    int32_t aclr_Rel_Limit[5];

    // Measure Setup (SEM)
//    uint8_t sem_avg_hold_mode;
//    uint8_t sem_avg_number;
    uint16_t sem_meas_type;
    uint16_t sem_trace_mode;
    uint16_t sem_trace_type;
    uint16_t sem_channel_detector;
    uint16_t sem_offset_detector;
    // Measure Setup (SEM) -> Ref Channel
    uint32_t sem_span;
    uint32_t sem_Integ_BW;
    uint16_t sem_RBW;
    uint16_t sem_VBW;
    // Measure Setup (SEM) -> Edit Mask
    uint16_t sem_Mask_Index[4];
    uint32_t sem_Mask_Start_Freq[4];
    uint32_t sem_Mask_Stop_Freq[4];
    uint16_t sem_Mask_Side[4];
    uint16_t sem_Mask_RBW[4];
    uint16_t sem_Mask_VBW[4];

    int16_t sem_Mask_Abs_Start_Limit[4];
    int16_t sem_Mask_Abs_Stop_Limit[4];
    int16_t sem_Mask_Rel_Start_Limit[4];
    int16_t sem_Mask_Rel_Stop_Limit[4];
    uint16_t sem_Mask_Fail_Source[4];

    // Transmit
    uint16_t ramp_up_start_time;
    uint16_t ramp_up_stop_time;
    uint16_t ramp_down_start_time;
    uint16_t ramp_down_stop_time;
    int16_t lim_off_power;
    int16_t lim_ramp_up_time;
    int16_t lim_ramp_down_time;

    // SPURIOUS_EMISSION Measure Setup
    uint64_t spuem_low_freq;
    uint64_t spuem_high_freq;

    uint16_t spuem_FRT_Index[6];
    uint64_t spuem_FRT_Start_Freq[6];
    uint64_t spuem_FRT_Stop_Freq[6];

    uint16_t spuem_FRT_RBW[6];
    uint16_t spuem_FRT_VBW[6];

    int16_t spuem_FRT_Abs_Start_Limit[6];
    int16_t spuem_FRT_Abs_Stop_Limit[6];

    commandHandler handler;
} CommandSASG;

typedef struct {
    ProtocolType type;
    uint32_t code; // Measurement mode
    uint16_t meas_mode;
    uint16_t meas_type;
    // Frequency
    uint64_t center_freq;

    // Amplitude
    uint16_t amp_mode;
    uint16_t amp_atten;
    uint16_t amp_preamp;

    int64_t freq_offset;
    int32_t carrier_threshold;
    int32_t image_threashold;

} CommandIQCal;

typedef struct {
    CommandVSWR *vswr;
    CommandSASG *sasg;
    CommandIQCal *iqcal;
} commands;

/* COMMANDS to be defined */
#define DATA_CAPUTRE_GRP		0x0000
#define MEASURE_DATA_START 		(DATA_CAPUTRE_GRP+0x11)
#define STOP_DATA_TRANSFER  	(DATA_CAPUTRE_GRP+0x12)

// Mode Command
#define MEASURE_GRP				0x0100
#define VSWR_MODE				(MEASURE_GRP + 0x01)
#define DTF_MODE				(MEASURE_GRP + 0x02)
#define CABLE_LOSSVSWR_MODE		(MEASURE_GRP + 0x03)
#define SA_MODE					(MEASURE_GRP + 0x04)
#define SG_MODE					(MEASURE_GRP + 0x05)

// VSWR Measure Type Command
#define VSWR_MEASURE_TYPE_GRP	0x0200
#define VSWR_TYPE 				(VSWR_MEASURE_TYPE_GRP+0x11)
#define RETURN_LOSS_TYPE	  	(VSWR_MEASURE_TYPE_GRP+0x12)

// Frequency Command
#define START_FREQ				"start_freq/"
#define STOP_FREQ				"stop_freq/"

// Data Points Command
#define DATA_POINTS_GRP			0x0300
#define DATA_POINTS_129			(DATA_POINTS_GRP + 0x00)
#define DATA_POINTS_257			(DATA_POINTS_GRP + 0x01)
#define DATA_POINTS_513			(DATA_POINTS_GRP + 0x02)
#define DATA_POINTS_1025		(DATA_POINTS_GRP + 0x03)
#define DATA_POINTS_2049		(DATA_POINTS_GRP + 0x04)

// User Cal selected
#define USER_CAL_GRP			0x0500
#define USER_CAL_OFF			(USER_CAL_GRP + 0x00)
#define USER_CAL_ON				(USER_CAL_GRP + 0x01)

// Calibration Command
#define CALIBRATION_RUN			0x110000

// SET PARAMS
#define SET_MEASURE_PARAMS		0x120000
#define SET_CAL_PARAMS			0x130000

// Windowing Command
#define WINDOWING_GRP			0x0600
#define WINDOW_RECTANGULAR		(WINDOWING_GRP + 0x00)
#define WINDOW_NOMINAL_SL		(WINDOWING_GRP + 0x01)
#define WINDOW_LOW_SL			(WINDOWING_GRP + 0x02)
#define WINDOW_MINIMUL_SL		(WINDOWING_GRP + 0x03)

// Preset Command
//#define PRESET_GRP				0x0700
//#define PRESET_DL995			(PRESET_GRP + 0x00)
//#define PRESET_DL1840			(PRESET_GRP + 0x01)
//#define PRESET_DL1855			(PRESET_GRP + 0x02)
//#define PRESET_DL2155			(PRESET_GRP + 0x03)
//#define PRESET_DL2165			(PRESET_GRP + 0x03)
//
//#define PRESET_UL910			(PRESET_GRP + 0x10)
//#define PRESET_UL1745			(PRESET_GRP + 0x11)
//#define PRESET_UL1760			(PRESET_GRP + 0x12)
//#define PRESET_UL1965			(PRESET_GRP + 0x13)
//#define PRESET_UL1975			(PRESET_GRP + 0x14)
//#define PRESET_NR3550			(PRESET_GRP + 0x20)

// System Command
#include <version_info.h>
#define REQ_FIRMWARE_VER		0x100000
//#define FIRMWARE_VER			"3.1.3"
#define FW_VER_CMD              "0x07 0x00 "FIRMWARE_VER
#define FIRMWARE_READY          0x200000

// Firmware Update
#define FW_DOWNLOAD_START		0x0700
#define FW_DOWNLOAD_READY		0x0701
#define FW_DOWNLOAD_DONE		0x0702
#define FW_DOWNLOAD_OK			0x0703

// Cable Command
// SG/SA Activation Command
// Battery Command

#define CHECK_SYSTEM_STATUS		0x13
#define CHECK_SYSTEM_TEMP		0x22
#define CAPTURE_REQUEST		 	0x99


// SA Command
// Calibration
#define CMD_USER_CAL 	    0x00

// Additional VSWR Cal.
#define CMD_FACTORY_CAL 	0x91
#define CMD_RESET_CAL 		0x92

// CMD Mode
#define CMD_VSWR 		    0x01
#define CMD_DTF			    0x02
#define CMD_CABLE_LOSS	    0x03
#define CMD_SA			    0x04
#define CMD_GATE_MODE       0x23
#define CMD_AUTO_ATTEN      0x24
#define CMD_5G_NR           0x041
#define CMD_MODE_ACCURACY   0x042
#define CMD_IQ_IM_CAL       0x043
#define CMD_SG			    0x05
#define CMD_BATT		    0x06
#define CMD_FW			    0x07

// 61.44MHz Test Mode (AD9361 Clock Test)
#define CMD_61_44_TEST      0x44
#define CMD_61_44_TEST_RESP "0x45"

// 61.44MHz Test Types
#define TYPE_61_44_INIT         0x00  // Initialize 61.44MHz mode
#define TYPE_61_44_SPECTRUM     0x01  // Spectrum measurement (8192 points)
#define TYPE_61_44_IQ_CAPTURE   0x02  // IQ data capture
#define TYPE_61_44_STOP         0x0F  // Stop measurement
#define CMD_USER_CAL_TYPE   0x08
#define CMD_USER_CAL_ONOFF  0x09
#define CMD_RESPONSE_ERR   "0x98"
#define CMD_RESPONSE       "0x99"

#define CMD_TAE_ON          0x71
#define CMD_TAE_ON_RESP     "0x72"

#define CMD_GPS_LOCK_STAT   "0x51" // FW --> APP (gps.c)
#define CMD_GPS_INFO_REQ	0x52 // APP --> FW, Request GPS status in detail
#define CMD_GPS_INFO_RESP	"0x53" //FW --> APP, Response for CMD_GPS_INFO_REQ
#define CMD_GPS_HO_REQ 		0x54 // APP --> FW, Request GPS Holdover Configuration
#define CMD_GPS_HO_RESP		"0x54" //FW --> APP, Ack for CMD_GPS_HO_REQ

#define CMD_RTK_GPS_REQ 	0x56 // Single Request
#define CMD_RTK_GPS_RESP 	0x57 // Single Response
#define CMD_RTK_GPS_START_STOP 	0x58 // Thread Start/Stop

#define CMD_UDP_IQ_CTRL 	0x93 // APP --> FW, UDP IQ Direct Capture & Transmission (format: 0x93 <sample_count> [mode] [freq_khz])
                                     // Example: 0x93 10000 4 2000000 (10000 samples, mode 4, 2GHz)
                                     // Defaults: mode=4 (CIC), freq=2000000 kHz (2 GHz)
#define CMD_UDP_IQ_RESP 	"0x94" // FW --> APP, Response for CMD_UDP_IQ_CTRL (format: 0x94 <samples> <packets>)

#define CMD_LNA_CON 		 0x81 // APP --> FW, Notify LNA Connection Status

// Mode Accuracy
#define TYPE_5G_DEMOD        0x07
#define TYPE_LTE_FDD         0x08 // remained
#define TYPE_TAE             0x09
#define TYPE_5G_NR_SCAN		 0x11
//Ryan Add@2023.12.06, to support LTE TDD
#define TYPE_LTE_TDD		 0x0A

//Ryan Modified, ass meas type for PURIOUS_EMMISION
enum MEASURE_TYPE_SA   { SWEPT_SA, CHANNEL_POWER, OCCUPIED_BW, ACLR, SEM, TRANSMIT_ON_OFF, SPURIOUS_EMISSION, CAL_SA=0x7 } ;
// SA Calibration
enum CAL_SA            { SA_CAL_READY=0x10, SA_FILE_START=0x11, SA_FILE_DONE=0x12, SA_CAL_COMPLETE=0x15 };
// Sweep
enum DATA_POINT        { DP129=0x00, DP257=0x01, DP513=0x02, DP1025=0x03, DP2049=0x04, DP2002=0x05 };
// Frequency
// 	RBW/VBW 1, 3 10, 30 100, 300, 1000, 3000 khz
// Amplitude
// 	Mode
enum AMP_MODE          { AMP_MANUAL, AMP_AUTO };
// Trace
// 	Trace 1
// 		mode
enum TRACE_MODE        { CLEAR_WHITE, AVERAGE, MAX_HOLD, MIN_HOLD };
enum TRACE_TYPE        { UPDATE, VIEW, BRAIN };
enum TRACE_DETECTER    { NORMAL, PEAK, NEGATIVE, SAMPLE, RMS };
// SWEEP Time
//		mode : same with AMP_MODE
//		sweep time : us

// MEASURE Setup
//	avg/hold mode	off / on
//  avg number 1 - 200


int init_protocol(ProtocolType type);
int send_command(int code);

void set_vswr_all_bandwith();
void set_aging_vswr(int count);

#endif /* SRC_COMMAND_COMMAND_H_ */
