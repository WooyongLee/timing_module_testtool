/*


 * mqtt_mgmt.c
 *
 *  Created on: Feb 11, 2019
 *      Author: codeart
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include <ctype.h>
#include <pthread.h>
#include <MQTTAsync.h>
#include <AlgoNR/algo5G.h>
#include <AlgoLTE/dsLte_Defs.h>
#include <AlgoLTE/AlgoLTE.h>
#include <AlgoSA/algoSA.h>
#include <HW/hw_mgmt.h>
#include <HW/GPS/gps.h>
#include <HW/PL/ad9629.h>
#include <HW/ad9361/ad9361_manager.h>
#include <command/MQTT/mqtt_mgmt.h>
#include <version_info.h>

#include "HW/RTK/rtk.h"
#include "sg.h"
#include "ho_control.h" //Ryan Add, to  check if Holdover control is working
#include "command/udp_iq_stream.h"
#include "HW/PL/pl_driver.h"
#include "command/test_6144.h"

#include "AlgoNR/algo5G.h"
#include "AlgoVSWR/dsSM_Defs.h"


#define MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
#define MQTT_DEF_DEFAULT_FTP_PATH "/run/media/mmcblk0p1" //Ryan Add, to support SG file transmission on receiving sg file from application via FTP
extern GPS_INFO gps_info;

//#define MODULE_NAME "MQTT"
// Project Specific
#ifdef RELEASE
#define DEBUG 0
#else
#define DEBUG 1
#endif

#include <common/debug.h>

// ALGO
#include "AlgoNR/dsNR_Defs.h"

#define BROKER_ADDR     "tcp://localhost:1883"
#define CLIENT_ID    	"PACT/LinuxApp"
#define TOPIC_CMD       "pact/command"
#define TOPIC_DATA1     "pact/data1"
#define TOPIC_DATA2     "pact/data2"
#define QOS             0
#define TIMEOUT         100000L

extern ds_NR_SetAPI* get_dl_demod_params(void);
ds_NR_Scan_SetAPI* get_dl_scan_params(void);
extern dsLte_UserInput_Param* get_LTE_params(void);

volatile int disc_finished = 0;
volatile int subscribed = 0;
volatile int finished = 0;
static CommandSASG *cmd_sasg;
static CommandVSWR *cmd_vswr;
static CommandIQCal *cmd_iqcal;

#ifdef SG_DEF_SG_ENABLED
static SG_PARAM sg_param; //Ryan Add, to add settings for SG functionality
#endif

// JBK =>
volatile int CUR_CMD_MODE = CMD_VSWR;
//volatile int CUR_CMD_MODE = CMD_SA;
// JBK <=
volatile int CUR_CMD_TYPE = 0;

MQTTAsync client;

int pubMqttDataByteArray(int *buffer, int len);
/*
VSWR        : 0x01 0x01 0x00 184000 186000 1000 7 88 0x00 0x00 0x01 0x00
DTF         : 0x02 0x04 0x00 184000 186000 1000 7 88 0x00 0x00 0x01 0x00
CableLoss   : 0x03 0x05 0x00 184000 186000 1000 7 88 0x00 0x00 0x01 0x00
Calibration : 0x00 0x01 0x00 184000 186000 1000 0 0  0x00 0x03 0x01 0x00
*/
//                          mod tp d.p. fq fq di cl ve  win
#define PARAMS_HOLDERS_VSWR "%x %x %x %llu %llu %u %u %u %x"
// 0x00 184000 186000 0x00 0x00 0x01
#define PARAMS_HOLDERS_CAL  "%x %u %u %x %x %x"
/*
Swept SA      : 0x04 0x06 0x00 230000 380000 30 1000 0x00 20 0x00 0x00 0x04 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01 100 0x01 100 0 0 0
Channel Power : 0x04 0x07 0x00 184000 3000 100 100 0x00 20 0x01 0x00 0x04 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01 100 0x01 100 0 0 3800000
Occupied BW   : 0x04 0x08 0x00 184000 3000 30 1000 0x00 20 0x01 0x00 0x04 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01 100 0x01 100 9900 -2600 0
*/

                      // "0x42 0x07 365000 0x01 20 0 0x00 0x12 0x01 24 0 5"
#define PARAMS_HOLDERS_DL_DEMOD "%x %x %llu %x %u %u %x %x %d %u %u %u"


// Set CMD_5G_DL_DEMOD Params
uint32_t dummy1 = 0;
uint32_t dummy2 = 0;
static uint32_t atten_mode = 0;
static uint32_t atten_val  = 0;
int atten_offset =  0;
uint32_t preamp = 0;

// User Cal
int user_cal_type = 0x01;

int SA_RUN_START = 0;
int SA_RUN_START_MODE = 0;

#define SPEED_ENHACED

extern int restart_reason;
extern int capture_vswr;
uint32_t meas_timestamp = 0;

void* run_sa_measure_func(void* arg)
{

    int temp = (int)arg;
    int ret=0;
    dev_printf("\t--> run_sa_measure_func %d\n", temp);

	while (ho_control_is_idle()) { //Ryan Modified, to  check if Holdover control is working

    	if (SA_RUN_START) {
            dev_printf("run_sa_measure_func() %d\n", SA_RUN_START_MODE);
            if (TRANSMIT_ON_OFF == CUR_CMD_TYPE) {
                tramsmit_on_off();
            } else {
#if 0
            	if(SA_RUN_START_MODE == CMD_GATE_MODE) {
            		SA_analyze2(CMD_GATE_MODE);
            	}
#else
            	if(cmd_sasg->gate_view) SA_analyze2(CMD_GATE_MODE);
#endif
            	ret = SA_analyze2(MEASURE_DATA_START);
            }
            if(restart_reason == 7) SA_RUN_START=0;
#ifndef SPEED_ENHACED
            SA_RUN_START = 0;
#endif
        }
        usleep(5);
    }
}

pthread_t sa_run_thread;
void run_sa_measure_thread(int type)
{
    int rc = pthread_create(&sa_run_thread, NULL, run_sa_measure_func, (void*) type);
    if (rc) {
        dev_printf("ERROR; return code from pthread_create() %d\n", rc);
        exit(-1);
    }

    return;
}

extern int TAE_PORT;
extern void fw_restart(int type);
static int __messageArrived(void *context, char *topicName, int topicLen, MQTTAsync_message *message)
{
//    dev_printf("Message arrived\n");
//    dev_printf("     topic: %s\n", topicName);
//    dev_printf("   message: \n");

    char mqtt_mesg[256];
    int auto_att = 0;
    int preamp_state = 0;


    /* Got a command from the client and parse the command/arguments */
    if (!strcmp(topicName, TOPIC_DATA1)) {
        goto EXIT_MQTT_RESP;
    }
    else if(!strcmp(topicName, TOPIC_CMD)) {
        char *mesg = (char *)message->payload;
        mesg[message->payloadlen] = '\0';

        dev_printf("%s Got MQTT %s Command ( %d bytes )\n",__FUNCTION__, mesg, message->payloadlen);

        static uint32_t cmd_mode = 999999;
        static uint32_t measure_type = 999999;

        sscanf(mesg, "%x %x", &cmd_mode, &measure_type);
        dev_printf("MQTT RCVED CMD_MODE: %x, TYPE %x, MESG: %s\n", cmd_mode, measure_type, mesg);
        // JBK =>
        //dev_printf("--------->>> RUN MODE : %d\n", get_RUN_MODE());
        // Exception code for Cal Error when start cal mode (RUN_MODE 7)
        //if (cmd_mode == 0x8290) {
        if (cmd_mode == 0x8290 || (get_RUN_MODE() == 7 && measure_type == 999999)) {
        // JBK =>
            //dev_printf("---------> RUN MODE : %d\n", get_RUN_MODE());
            goto EXIT_MQTT_RESP;
        }
        dev_printf("\n");
        dev_printf("MQTT COMMAND TOPIC : handling command mode 0x%02x type 0x%02x\n", cmd_mode, measure_type);

        if (cmd_mode == CMD_USER_CAL) { //TODO: User Cal

            sscanf(mesg, "%x %hhx",
                            &cmd_vswr->code,
                            &cmd_vswr->cal_step
            );

            cmd_vswr->cal_type = user_cal_type;
            cmd_vswr->code = CALIBRATION_RUN;
            cmd_vswr->cal_step--;

            cmd_vswr->handler(cmd_vswr);

        }

        else if (cmd_mode == 0x8290) {
        	/* Ryan add, Simple Packet RX Test to check response time */
        	pubMqttString("0x8290", strlen("0x8290"));
        	/* Ryan add */
        } else if (cmd_mode == CMD_TAE_ON) {
            sscanf(mesg, "%x %d",
                            &cmd_vswr->code,
                            &TAE_PORT
            );

            set_TAE_mode(1);
            is_TAE_mode();
            pubMqttString(CMD_TAE_ON_RESP, strlen(CMD_TAE_ON_RESP));

        }
        else if (cmd_mode == 0x08) { //TODO: FLEX or Standard

            sscanf(mesg, "%x %x",
                            &cmd_vswr->code,
                            &user_cal_type
            );

            cmd_vswr->cal_type = user_cal_type;
//            cmd_vswr->code = CALIBRATION_RUN;
//            cmd_vswr->cal_step--;

//            cmd_vswr->handler(cmd_vswr);
        } else if (cmd_mode == 0x09) { // On / oFf

            int on = 0;
            sscanf(mesg, "%x %x",
                            &cmd_vswr->code,
                            &on
            );

            cmd_vswr->cal_type = user_cal_type;
            if (on == 0x01) {
                cmd_vswr->code = USER_CAL_ON;
            } else {
                cmd_vswr->code = USER_CAL_OFF;
            }

            cmd_vswr->handler(cmd_vswr);
        }
        else if(cmd_mode == 0x65) {
            dev_printf("FW Will be restarted\n");
            int type = 0;
            sscanf(mesg, "%x %x",
                            &cmd_vswr->code,
                            &type
            );
            dev_printf("0x%x %d\n", cmd_vswr->code, type);
            //
            pubMqttEmtptyQueue();

//            if (type != get_M_MODE())
            fw_restart(type);

        } else if (cmd_mode == 0x77)
        {
        	capture_vswr = 1;
        	printf("vswr capture requested");
            sprintf(mqtt_mesg, "0x77 %d", capture_vswr);
            pubMqttString(mqtt_mesg, strlen(mqtt_mesg));

            vswr_test(get_DRAM_buffer(), 8192);
            capture_vswr = 0;
        } else if(cmd_mode == 0x50) {
            static uint32_t cmd_mode = 0;
            static uint32_t gps_type = 0;
            sscanf(mesg, "%x %d", &cmd_mode, &gps_type);
            select_clock_src(gps_type);
            dev_printf("Clock Src (GPS) selected as %d\n", gps_type);
            sprintf(mqtt_mesg, "0x50 %d", gps_type);
            pubMqttString(mqtt_mesg, strlen(mqtt_mesg));
        } else if(cmd_mode == CMD_AUTO_ATTEN) {
            if(CUR_CMD_MODE == CMD_SA) {
                STOP_SA();
                get_auto_atten(&auto_att, &preamp_state);
                sprintf(mqtt_mesg, "0x24 %d %d", auto_att, preamp_state);
                pubMqttString(mqtt_mesg, strlen(mqtt_mesg));
            }
        }
        else if(cmd_mode == MEASURE_DATA_START || cmd_mode == 0x12) {
        	if(cmd_mode == 0x12) {
        		uint32_t cmd_mode = 0;
                sscanf(mesg, "%x %d", &cmd_mode, &meas_timestamp);
				printf("MEASURE_DATA_START 0x12, Timestamp %u\n", meas_timestamp);
        	}else{
				dev_printf("Start : GATE MEASURE_DATA_START NORMAL MODE\n");
				dev_printf("MEASURE_DATA_START 0x11\n");
        	}
            pubMqttString("0x11", strlen("0x11"));

            if(CUR_CMD_MODE == CMD_MODE_ACCURACY) {
                if (CUR_CMD_TYPE == TYPE_5G_DEMOD) {
                	set_SCAN_mode(0);
                    set_5G_RUN(1);
                    dev_printf("\t\t\t\t\tAsync Demod called\n");
                } else if (CUR_CMD_TYPE == TYPE_LTE_FDD || CUR_CMD_TYPE == TYPE_LTE_TDD) { //Ryan Modified@20240109, to support LTE TDD
                    set_LTE_RUN(1);
                    dev_printf("\t\t\t\t\tAsync LTE called\n");
                } else if (CUR_CMD_TYPE == TYPE_TAE) {
                    set_5G_RUN(1);
                    dev_printf("\t\t\t\t\tAsync LTE called\n");
                } else if (CUR_CMD_TYPE == TYPE_5G_NR_SCAN) {
                    set_5G_RUN(1);
                    dev_printf("\t\t\t\t\t5G SCAN called\n");
                } else {
                    dev_printf("Not Avaialble TYPE\n");
                }
            } else if(CUR_CMD_MODE == CMD_SA) {
            	set_SCAN_mode(0);

                if (is_sa_doing()) {
                    dev_printf("\n\t\t\t CMD_SA already in progress, pass the request 0x11\n");
//                    pubMqttDataByteArray(dummy, sizeof(dummy));
                    goto EXIT_MQTT_RESP;
//                    pubMqttString(CMD_RESPONSE_ERR, strlen(CMD_RESPONSE_ERR));
                }
                dev_printf(" %d %d\n", CUR_CMD_MODE, CUR_CMD_TYPE);
                switch (CUR_CMD_TYPE) {
                    case SWEPT_SA:
                        //TODO:fix
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
//                        run_sa_measure_thread(MEASURE_DATA_START);
//                        SA_analyze(MEASURE_DATA_START);
                        break;
                    case CHANNEL_POWER:
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
//                        SA_analyze(MEASURE_DATA_START);
                        break;
                    case OCCUPIED_BW:
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
//                        SA_analyze(MEASURE_DATA_START);
                        break;
                    case ACLR:
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
//                        SA_analyze(MEASURE_DATA_START);
                        break;
                    case SEM:
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
                        break;
                    case TRANSMIT_ON_OFF:
                        // TODO : as thread mode
                        dev_printf("TRAMS--------------OFF mode %d\n", CUR_CMD_TYPE);
                        SA_RUN_START_MODE = MEASURE_DATA_START;
                        SA_RUN_START = 1;
//                        tramsmit_on_off();
                        break;
                }
            }
            else {
                cmd_vswr->code = cmd_mode;
                cmd_vswr->handler(cmd_vswr);
            }
        }
        else if (cmd_mode == CMD_GATE_MODE) {
            dev_printf("Start : GATE MEASURE_DATA_START CMD_GATE_MODE\n");
            if (is_sa_doing()) {
                dev_printf("\t\t\t\tit's already in progress, pass the request 0x23\n");
                usleep(1000 * 1000);
//                int dummy[2002] = {-99999,};
//                for (int i=0; i<2002; i++) {
//                     dummy[i] = -99999;
//                 }
//                dummy[0] = CUR_CMD_MODE;
//                dummy[1] = CUR_CMD_TYPE;

//                pubMqttDataByteArray(dummy, sizeof(dummy));
//                goto EXIT_MQTT_RESP;
            }
//            SA_analyze(CMD_GATE_MODE);
            SA_RUN_START_MODE = CMD_GATE_MODE;
            SA_RUN_START = 1;
        }
        else if (cmd_mode >= CMD_VSWR && cmd_mode <= CMD_CABLE_LOSS) { // SET MEASURE PARAMS
            //TODO: FIX
            if(CUR_CMD_MODE < CMD_VSWR && CUR_CMD_MODE > CMD_CABLE_LOSS) {
//                fw_restart(0);
                dev_printf("\n\t\t\t\t\t Previous mode is not in VSWRs\n\n");
//                fw_restart(0);
//                init_ad9361_module(0);
            }

            if (get_RUN_MODE() != 0) {
                pubMqttString(CMD_RESPONSE_ERR, strlen(CMD_RESPONSE_ERR));
                goto EXIT_MQTT_RESP;
            }
            CUR_CMD_MODE = cmd_mode;
            CUR_CMD_TYPE = measure_type;

            dev_printf("Set Params for VSWR \n");
            sscanf(mesg, "%hhx %hhx %hhx %llu %llu %u %u %u %hhx",
                            &cmd_vswr->meas_mode, &cmd_vswr->meas_type, &cmd_vswr->data_point,
                            &cmd_vswr->start_freq, &cmd_vswr->stop_freq, &cmd_vswr->distance,
                            &cmd_vswr->cable_loss, &cmd_vswr->prop_velocity, &cmd_vswr->windowing
            );
            //        	dev_printf("TEST : %x %x %x %llu %llu %u %u %u %x",
            dev_printf("%x %x %x %llu %llu %u %u %u %x",
                            cmd_vswr->meas_mode,  cmd_vswr->meas_type,     cmd_vswr->data_point,
                            cmd_vswr->start_freq, cmd_vswr->stop_freq,     cmd_vswr->distance,
                            cmd_vswr->cable_loss, cmd_vswr->prop_velocity, cmd_vswr->windowing
            );
            dev_printf("\n");

//            cmd_vswr->start_freq = cmd_vswr->start_freq * 1 * 1000; // *100 from App (for float)
//            cmd_vswr->stop_freq  = cmd_vswr->stop_freq  * 1 * 1000;

            cmd_vswr->code = SET_MEASURE_PARAMS;
            cmd_vswr->handler(cmd_vswr);

            //            if (!same_mode) {
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
            //            }

        }
        else if (cmd_mode == CMD_SA && (SWEPT_SA <= measure_type && measure_type <= OCCUPIED_BW )) { // SET SA PARAMS
            if (is_sa_doing()) {
                dev_printf("CMD_SA __________________ is in Process\n");
//                usleep(1000*1000);
//                pubMqttString(CMD_RESPONSE_ERR, strlen(CMD_RESPONSE_ERR));
//                goto EXIT_MQTT_RESP;
            }

            if (CUR_CMD_MODE == CMD_MODE_ACCURACY) {
//                pubMqttEmtptyQueue();
                dev_printf("\n\t\t\t\t\t Previous mode is 5GNR\n\n");
//                fw_restart(0);
//                system("reboot");
//                system()
            }
//            bool same_mode = true;

            if(CUR_CMD_MODE != CMD_SA) {
//                init_ad9361_module(1);
//                same_mode = false;
            } else {
                if(CUR_CMD_TYPE != measure_type) {
//                    same_mode = false;
                }
            }

            CUR_CMD_MODE = CMD_SA;
            CUR_CMD_TYPE = measure_type;

            //           mode type d.p. cf sp rbw  vbw  mod  att  t1_m t1_t t1_d t2_m t2_t t2_d t3_m t3_t t3_d t4_m t4_t t4_d mod  t  m    n    o   x   i

            // 0x04 0x00
            // 230000 380000
            // 1000 1000 0x00 20 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 1 5000 1 100 0 0 0
            // 0x04 0x00 230000 380000 1000 1000 0 20 0 0 0 0 0 0 0 0 0 0 0 0 1 5000 1 100 0 0 0

            cmd_sasg->center_freq = 0;

            sscanf(mesg,
                "%hx %hx "
                "%llu %llu "
                "%hu %hu "
                "%hu %hu %hu %d "

                "%hu %hu %hu "
                "%hu %hu %hu "
                "%hu %hu %hu "
                "%hu %hu %hu "

                "%hu %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
            	"%hu %hu %d "
            	"%hu %hu %d "
            	"%d %d "
          #ifndef GATE_SYMB
            	"%hu %hu %hu %hu "
          #endif
            	"%d "
#else
            	"%hu %hu %d %d %d %d "
#endif
                "%hu %hu %hu %hu %d"
                ,
                &cmd_sasg->code,        &cmd_sasg->meas_type,
                &cmd_sasg->center_freq, &cmd_sasg->span,
                &cmd_sasg->rbw,         &cmd_sasg->vbw,
                &cmd_sasg->amp_mode, &cmd_sasg->amp_atten, &cmd_sasg->amp_preamp, &cmd_sasg->amp_offset,

                &cmd_sasg->trace1_mode, &cmd_sasg->trace1_type, &cmd_sasg->trace1_detector,
                &cmd_sasg->trace2_mode, &cmd_sasg->trace2_type, &cmd_sasg->trace2_detector,
                &cmd_sasg->trace3_mode, &cmd_sasg->trace3_type, &cmd_sasg->trace3_detector,
                &cmd_sasg->trace4_mode, &cmd_sasg->trace4_type, &cmd_sasg->trace4_detector,

                &cmd_sasg->sweep_time_mode, &cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                &cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time,
				&cmd_sasg->gate_num, &cmd_sasg->gate_type, &cmd_sasg->gate_delta,
				&cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
				&cmd_sasg->gate_delay_slot, &cmd_sasg->gate_delay_symbol, &cmd_sasg->gate_length_slot, &cmd_sasg->gate_length_symbol,
#endif
				&cmd_sasg->gate_source,
#else
                &cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time, &cmd_sasg->gate_delay, &cmd_sasg->gate_length, &cmd_sasg->gate_source,
#endif
				&cmd_sasg->avg_hold_mode, &cmd_sasg->avg_number, &cmd_sasg->obw_power, &cmd_sasg->xdb, &cmd_sasg->integration_bw
            );

            printf(
                "0x%02x 0x%02x\n"
                "Freq : %llu Span : %llu\n"
                "RBW : %d VBW : %d\n"
                "Amp mode : %d Atten : %d Preamp : %d Amp Offset : %d\n"

                "Trace 1 Mode : %d Trace 1 Type : %d Trace 1 Detector : %d\n"
                "Trace 2 Mode : %d Trace 2 Type : %d Trace 2 Detector : %d\n"
                "Trace 3 Mode : %d Trace 3 Type : %d Trace 3 Detector : %d\n"
                "Trace 4 Mode : %d Trace 4 Type : %d Trace 4 Detector : %d\n"

                "Sweep Mode : %d Sweep Time : %d \n"
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                "Gate Mode : %d Gate View : %d Gate View Sweep Time : %u \n"
                "Gate Num : %d Gate Type : %d Gate Delta : %d \n"
                "Gate Delay : %d Gate Length : %d \n"
#ifndef GATE_SYMB
                "Gate Delay Slot : %d Gate Delay Symbol : %d Gate Length Slot : %d Gate Length Symbol : %d \n"
#endif
                "Gate Source : %d \n"
#else
                "%d %d %d %d %d %d\n"
#endif
                "Avg Hold Mode : %d Avg Num : %d OBW Power : %d x dB : %d Integ.BW : %d\n"
                ,
                cmd_sasg->code, cmd_sasg->meas_type,
                cmd_sasg->center_freq, cmd_sasg->span,
                cmd_sasg->rbw, cmd_sasg->vbw,
                cmd_sasg->amp_mode, cmd_sasg->amp_atten, cmd_sasg->amp_preamp, cmd_sasg->amp_offset,

                cmd_sasg->trace1_mode, cmd_sasg->trace1_type, cmd_sasg->trace1_detector,
                cmd_sasg->trace2_mode, cmd_sasg->trace2_type, cmd_sasg->trace2_detector,
                cmd_sasg->trace3_mode, cmd_sasg->trace3_type, cmd_sasg->trace3_detector,
                cmd_sasg->trace4_mode, cmd_sasg->trace4_type, cmd_sasg->trace4_detector,

                cmd_sasg->sweep_time_mode, cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
				cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time,
				cmd_sasg->gate_num, cmd_sasg->gate_type, cmd_sasg->gate_delta,
				cmd_sasg->gate_delay, cmd_sasg->gate_length,
#ifndef GATE_SYMB
				cmd_sasg->gate_delay_slot, cmd_sasg->gate_delay_symbol, cmd_sasg->gate_length_slot, cmd_sasg->gate_length_symbol,
#endif
				cmd_sasg->gate_source,
#else
                cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time, cmd_sasg->gate_delay, cmd_sasg->gate_length, cmd_sasg->gate_source,
#endif
				cmd_sasg->avg_hold_mode, cmd_sasg->avg_number, cmd_sasg->obw_power, cmd_sasg->xdb, cmd_sasg->integration_bw
            );

//            cmd_sasg->center_freq = cmd_sasg->center_freq * 1 * 1000; // * 100
//            cmd_sasg->span = cmd_sasg->span * 1 * 1000;
#if 0 //Ryan removed, to move this logic to set_ad9361_freqeuncy()
            if (cmd_sasg->center_freq == 10*1000*1000) {
                dev_printf("10 Mhz is set, Enable AD9629");
                if (get_ad9629_mode() == 0)
                    ad9629_enable();
            } else {
                if (get_ad9629_mode() == 1)
                    ad9629_disable();
            }
#endif
            set_SA_params(cmd_sasg);


#if 0
            /* Ryan Add, to support burst mode when gate view is visible */
            if(cmd_sasg->gate_view) SA_RUN_START_MODE = CMD_GATE_MODE;
            else SA_RUN_START_MODE = MEASURE_DATA_START;
            /* Ryan Add */
#endif

            dev_printf("RUN_MODE %d\n", get_RUN_MODE());
            if (get_RUN_MODE() == 1) {
                STOP_SA();
            }
            else {
                dev_printf("SA Cal is running\n");
            }
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
        }
        else if (cmd_mode == CMD_SA && measure_type == ACLR) { // SET SA PARAMS
            dev_printf("CMD_SA --> ACLR\n");
//            bool same_mode = true;
//            if(CUR_CMD_MODE != CMD_SA) {
////                init_ad9361_module(1);
//                same_mode = false;
//            } else {
//                if(CUR_CMD_TYPE != measure_type) {
//                    same_mode = false;
//                }
//            }
            CUR_CMD_MODE = CMD_SA;
            CUR_CMD_TYPE = ACLR;

            sscanf(mesg,
                    "%hx %hx "
                    "%llu %llu "
                    "%hu %hu "
                    "%hu %hu %hu %hu "

                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "

                    // sweep
                    "%hu %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                	"%hu %hu %d "
                	"%hu %hu %d "
                	"%d %d "
#ifndef GATE_SYMB
                	"%hu %hu %hu %hu "
#endif
                	"%d "
#else
                    "%hu %hu %d %d %d %d "
#endif
                    // measure setup
                    "%hu %hu "
                    // carrier
                    "%hu %hu %d %d "
                    // offset
                    "%hu"
                    "%d %d %d %d %d %d "
                    "%d %d %d %d %d %d "
                    "%d %d %d %d %d %d "
                    "%d %d %d %d %d %d "
                    "%d %d %d %d %d %d "
                    ,
                    &cmd_sasg->code, &cmd_sasg->meas_type,
                    &cmd_sasg->center_freq, &cmd_sasg->span,
                    &cmd_sasg->rbw, &cmd_sasg->vbw,
                    &cmd_sasg->amp_mode, &cmd_sasg->amp_atten, &cmd_sasg->amp_preamp, &cmd_sasg->amp_offset,

                    &cmd_sasg->trace1_mode, &cmd_sasg->trace1_type, &cmd_sasg->trace1_detector,
                    &cmd_sasg->trace2_mode, &cmd_sasg->trace2_type, &cmd_sasg->trace2_detector,
                    &cmd_sasg->trace3_mode, &cmd_sasg->trace3_type, &cmd_sasg->trace3_detector,
                    &cmd_sasg->trace4_mode, &cmd_sasg->trace4_type, &cmd_sasg->trace4_detector,

                    &cmd_sasg->sweep_time_mode, &cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					&cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time,
					&cmd_sasg->gate_num, &cmd_sasg->gate_type, &cmd_sasg->gate_delta,
					&cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
					&cmd_sasg->gate_delay_slot, &cmd_sasg->gate_delay_symbol, &cmd_sasg->gate_length_slot, &cmd_sasg->gate_length_symbol,
#endif
					&cmd_sasg->gate_source,
#else
                    &cmd_sasg->gate_mode, &cmd_sasg->gate_view,  &cmd_sasg->gate_view_sweep_time, &cmd_sasg->gate_delay, &cmd_sasg->gate_length, &cmd_sasg->gate_source,
#endif
					// measure setup
                    &cmd_sasg->avg_hold_mode, &cmd_sasg->avg_number,
                    // carrier
                    &cmd_sasg->aclr_Carriers, &cmd_sasg->aclr_Ref_Carriers, &cmd_sasg->aclr_Carrier_Sapcing, &cmd_sasg->aclr_Integ_BW,
                    // offset
                    &cmd_sasg->aclr_Number_of_Offset,
                    &cmd_sasg->aclr_Offset_Spacing[0], &cmd_sasg->aclr_Offset_Integ_BW[0], &cmd_sasg->aclr_Offset_Side[0], &cmd_sasg->aclr_Fail_Source[0], &cmd_sasg->aclr_Abs_Limit[0], &cmd_sasg->aclr_Rel_Limit[0],
                    &cmd_sasg->aclr_Offset_Spacing[1], &cmd_sasg->aclr_Offset_Integ_BW[1], &cmd_sasg->aclr_Offset_Side[1], &cmd_sasg->aclr_Fail_Source[1], &cmd_sasg->aclr_Abs_Limit[1], &cmd_sasg->aclr_Rel_Limit[1],
                    &cmd_sasg->aclr_Offset_Spacing[2], &cmd_sasg->aclr_Offset_Integ_BW[2], &cmd_sasg->aclr_Offset_Side[2], &cmd_sasg->aclr_Fail_Source[2], &cmd_sasg->aclr_Abs_Limit[2], &cmd_sasg->aclr_Rel_Limit[2],
                    &cmd_sasg->aclr_Offset_Spacing[3], &cmd_sasg->aclr_Offset_Integ_BW[3], &cmd_sasg->aclr_Offset_Side[3], &cmd_sasg->aclr_Fail_Source[3], &cmd_sasg->aclr_Abs_Limit[3], &cmd_sasg->aclr_Rel_Limit[3],
                    &cmd_sasg->aclr_Offset_Spacing[4], &cmd_sasg->aclr_Offset_Integ_BW[4], &cmd_sasg->aclr_Offset_Side[4], &cmd_sasg->aclr_Fail_Source[4], &cmd_sasg->aclr_Abs_Limit[4], &cmd_sasg->aclr_Rel_Limit[4]
            );


            dev_printf("0x%02x 0x%02x\n"
                    "%llu %llu\n"
                    "%d %d\n"
                    "%d %d %d %d\n"

                    "%d %d %d\n"
                    "%d %d %d\n"
                    "%d %d %d\n"
                    "%d %d %d\n"

                    // sweep        /
                    "%d %d \n"
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                	"%d %d %d "
                	"%d %d %d "
                	"%d %d "
#ifndef GATE_SYMB
                	"%d %d %d %d "
#endif
                	"%d "
#else
                    "%d %d %d %d %d %d\n"
#endif
                    // measure
                    "%d %d\n"
                    // carrier
                    "%d %d %d %d\n"
                    // offset
                    "%d\n"
                    "%d %d %d %d %d %d\n"
                    "%d %d %d %d %d %d\n"
                    "%d %d %d %d %d %d\n"
                    "%d %d %d %d %d %d\n"
                    "%d %d %d %d %d %d\n"
                    ,
                    cmd_sasg->code, cmd_sasg->meas_type,
                    cmd_sasg->center_freq, cmd_sasg->span,
                    cmd_sasg->rbw, cmd_sasg->vbw,
                    cmd_sasg->amp_mode, cmd_sasg->amp_atten, cmd_sasg->amp_preamp, cmd_sasg->amp_offset,

                    cmd_sasg->trace1_mode, cmd_sasg->trace1_type, cmd_sasg->trace1_detector,
                    cmd_sasg->trace2_mode, cmd_sasg->trace2_type, cmd_sasg->trace2_detector,
                    cmd_sasg->trace3_mode, cmd_sasg->trace3_type, cmd_sasg->trace3_detector,
                    cmd_sasg->trace4_mode, cmd_sasg->trace4_type, cmd_sasg->trace4_detector,

                    cmd_sasg->sweep_time_mode, cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time,
					cmd_sasg->gate_num, cmd_sasg->gate_type, cmd_sasg->gate_delta,
					cmd_sasg->gate_delay, cmd_sasg->gate_length,
#ifndef GATE_SYMB
					cmd_sasg->gate_delay_slot, cmd_sasg->gate_delay_symbol, cmd_sasg->gate_length_slot, cmd_sasg->gate_length_symbol,
#endif
					cmd_sasg->gate_source,
#else
                    cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time, cmd_sasg->gate_delay, cmd_sasg->gate_length, cmd_sasg->gate_source,
#endif
					// measure setup
                    cmd_sasg->avg_hold_mode, cmd_sasg->avg_number,
                    // carrier
                    cmd_sasg->aclr_Carriers, cmd_sasg->aclr_Ref_Carriers, cmd_sasg->aclr_Carrier_Sapcing, cmd_sasg->aclr_Integ_BW,
                    // offset
                    cmd_sasg->aclr_Number_of_Offset,
                    cmd_sasg->aclr_Offset_Spacing[0], cmd_sasg->aclr_Offset_Integ_BW[0], cmd_sasg->aclr_Offset_Side[0], cmd_sasg->aclr_Fail_Source[0], cmd_sasg->aclr_Abs_Limit[0], cmd_sasg->aclr_Rel_Limit[0],
                    cmd_sasg->aclr_Offset_Spacing[1], cmd_sasg->aclr_Offset_Integ_BW[1], cmd_sasg->aclr_Offset_Side[1], cmd_sasg->aclr_Fail_Source[1], cmd_sasg->aclr_Abs_Limit[1], cmd_sasg->aclr_Rel_Limit[1],
                    cmd_sasg->aclr_Offset_Spacing[2], cmd_sasg->aclr_Offset_Integ_BW[2], cmd_sasg->aclr_Offset_Side[2], cmd_sasg->aclr_Fail_Source[2], cmd_sasg->aclr_Abs_Limit[2], cmd_sasg->aclr_Rel_Limit[2],
                    cmd_sasg->aclr_Offset_Spacing[3], cmd_sasg->aclr_Offset_Integ_BW[3], cmd_sasg->aclr_Offset_Side[3], cmd_sasg->aclr_Fail_Source[3], cmd_sasg->aclr_Abs_Limit[3], cmd_sasg->aclr_Rel_Limit[3],
                    cmd_sasg->aclr_Offset_Spacing[4], cmd_sasg->aclr_Offset_Integ_BW[4], cmd_sasg->aclr_Offset_Side[4], cmd_sasg->aclr_Fail_Source[4], cmd_sasg->aclr_Abs_Limit[4], cmd_sasg->aclr_Rel_Limit[4]
            );


//            cmd_sasg->center_freq = cmd_sasg->center_freq * 1 * 1000;
//            cmd_sasg->span = cmd_sasg->span * 1 * 1000;
            set_SA_params(cmd_sasg);

            /* Ryan Add, to support burst mode when gate view is visible */
            if(cmd_sasg->gate_view) SA_RUN_START_MODE = CMD_GATE_MODE;
            else SA_RUN_START_MODE = MEASURE_DATA_START;
            /* Ryan Add */

            STOP_SA();
//            if (!same_mode) {
                pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
//            }

        }
        else if (cmd_mode == CMD_SA && measure_type == SEM) { // SET SA PARAMS
/*
            bool same_mode = true;
            if(CUR_CMD_MODE != CMD_SA) {
//                init_ad9361_module(1);
                same_mode = false;
            }  else {
                if(CUR_CMD_TYPE != measure_type) {
                    same_mode = false;
                }
            }
*/

            CUR_CMD_MODE = CMD_SA;
            CUR_CMD_TYPE = SEM;
            dev_printf("CMD_SA --> SEM\n");

            sscanf(mesg,
                    "%hx %hx "
                    "%llu %llu "
                    "%hu %hu "
                    "%hu %hu %hu %hu "

                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "

                    "%hu %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                	"%hu %hu %d "
                	"%hu %hu %d "
                	"%d %d "
#ifndef GATE_SYMB
                	"%hu %hu %hu %hu "
#endif
                	"%d "
#else
                    "%hu %hu %d %d %d %d "
#endif
                    // measure setup
                    "%hu %hu %hu %hu %hu "
                    "%hu %hu "
                    // Ref. Channel
                    "%d %d %hu %hu "
                    // Edit Mask
                    "%hu %d %d %hu %hu %hu "
                    "%hu %hu %hu %hu %hu "

                    "%hu %d %d %hu %hu %hu "
                    "%hu %hu %hu %hu %hu "

                    "%hu %d %d %hu %hu %hu "
                    "%hu %hu %hu %hu %hu "

                    "%hu %d %d %hu %hu %hu "
                    "%hu %hu %hu %hu %hu "
                    ,
                    &cmd_sasg->code, &cmd_sasg->meas_type,
                    &cmd_sasg->center_freq, &cmd_sasg->span,
                    &cmd_sasg->rbw, &cmd_sasg->vbw,
                    &cmd_sasg->amp_mode, &cmd_sasg->amp_atten, &cmd_sasg->amp_preamp, &cmd_sasg->amp_offset,

                    &cmd_sasg->trace1_mode, &cmd_sasg->trace1_type, &cmd_sasg->trace1_detector,
                    &cmd_sasg->trace2_mode, &cmd_sasg->trace2_type, &cmd_sasg->trace2_detector,
                    &cmd_sasg->trace3_mode, &cmd_sasg->trace3_type, &cmd_sasg->trace3_detector,
                    &cmd_sasg->trace4_mode, &cmd_sasg->trace4_type, &cmd_sasg->trace4_detector,

                    &cmd_sasg->sweep_time_mode, &cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					&cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time,
					&cmd_sasg->gate_num, &cmd_sasg->gate_type, &cmd_sasg->gate_delta,
					&cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
					&cmd_sasg->gate_delay_slot, &cmd_sasg->gate_delay_symbol, &cmd_sasg->gate_length_slot, &cmd_sasg->gate_length_symbol,
#endif
					&cmd_sasg->gate_source,
#else
                    &cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time, &cmd_sasg->gate_delay, &cmd_sasg->gate_length, &cmd_sasg->gate_source,
#endif
					// measure setup
                    &cmd_sasg->avg_hold_mode, &cmd_sasg->avg_number, &cmd_sasg->sem_meas_type, &cmd_sasg->sem_trace_mode, &cmd_sasg->sem_trace_type,
                    &cmd_sasg->sem_channel_detector, &cmd_sasg->sem_offset_detector,
                    // Ref. Channel
                    &cmd_sasg->sem_span, &cmd_sasg->sem_Integ_BW, &cmd_sasg->sem_RBW, &cmd_sasg->sem_VBW,
                    // Edit Mask
                    &cmd_sasg->sem_Mask_Index[0], &cmd_sasg->sem_Mask_Start_Freq[0], &cmd_sasg->sem_Mask_Stop_Freq[0], &cmd_sasg->sem_Mask_Side[0], &cmd_sasg->sem_Mask_RBW[0], &cmd_sasg->sem_Mask_VBW[0],
                    &cmd_sasg->sem_Mask_Abs_Start_Limit[0], &cmd_sasg->sem_Mask_Abs_Stop_Limit[0], &cmd_sasg->sem_Mask_Rel_Start_Limit[0], &cmd_sasg->sem_Mask_Rel_Stop_Limit[0], &cmd_sasg->sem_Mask_Fail_Source[0],

                    &cmd_sasg->sem_Mask_Index[1], &cmd_sasg->sem_Mask_Start_Freq[1], &cmd_sasg->sem_Mask_Stop_Freq[1], &cmd_sasg->sem_Mask_Side[1], &cmd_sasg->sem_Mask_RBW[1], &cmd_sasg->sem_Mask_VBW[1],
                    &cmd_sasg->sem_Mask_Abs_Start_Limit[1], &cmd_sasg->sem_Mask_Abs_Stop_Limit[1], &cmd_sasg->sem_Mask_Rel_Start_Limit[1], &cmd_sasg->sem_Mask_Rel_Stop_Limit[1], &cmd_sasg->sem_Mask_Fail_Source[1],

                    &cmd_sasg->sem_Mask_Index[2], &cmd_sasg->sem_Mask_Start_Freq[2], &cmd_sasg->sem_Mask_Stop_Freq[2], &cmd_sasg->sem_Mask_Side[2], &cmd_sasg->sem_Mask_RBW[2], &cmd_sasg->sem_Mask_VBW[2],
                    &cmd_sasg->sem_Mask_Abs_Start_Limit[2], &cmd_sasg->sem_Mask_Abs_Stop_Limit[2], &cmd_sasg->sem_Mask_Rel_Start_Limit[2], &cmd_sasg->sem_Mask_Rel_Stop_Limit[2], &cmd_sasg->sem_Mask_Fail_Source[2],

                    &cmd_sasg->sem_Mask_Index[3], &cmd_sasg->sem_Mask_Start_Freq[3], &cmd_sasg->sem_Mask_Stop_Freq[3], &cmd_sasg->sem_Mask_Side[3], &cmd_sasg->sem_Mask_RBW[3], &cmd_sasg->sem_Mask_VBW[3],
                    &cmd_sasg->sem_Mask_Abs_Start_Limit[3], &cmd_sasg->sem_Mask_Abs_Stop_Limit[3], &cmd_sasg->sem_Mask_Rel_Start_Limit[3], &cmd_sasg->sem_Mask_Rel_Stop_Limit[3], &cmd_sasg->sem_Mask_Fail_Source[3]
            );

            printf("0x%02x 0x%02x \n"
                    "%llu %llu \n"
                    "%d %d \n"
                    "%d %d %d %d\n"

                    "%d %d %d \n"
                    "%d %d %d \n"
                    "%d %d %d \n"
                    "%d %d %d \n"
                    // sweep
                    "%d %d \n"
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                	"%d %d %d "
                	"%d %d %d "
                	"%d %d "
#ifndef GATE_SYMB
                	"%d %d %d %d "
#endif
                	"%d "
#else
                    "%d %d %d %d %d %d \n"
#endif
                    // measure setup
                    "%d %d %d %d %d \n"
                    "%d %d \n"
                    // Ref. Channel
                    "%d %d %d %d \n"
                    // Edit Mask
                    "%d %d %d %d %d %d \n"
                    "%d %d %d %d %d \n"

                    "%d %d %d %d %d %d \n"
                    "%d %d %d %d %d \n"

                    "%d %d %d %d %d %d \n"
                    "%d %d %d %d %d \n"

                    "%d %d %d %d %d %d \n"
                    "%d %d %d %d %d \n"
                    ,
                    cmd_sasg->code, cmd_sasg->meas_type,
                    cmd_sasg->center_freq, cmd_sasg->span,
                    cmd_sasg->rbw, cmd_sasg->vbw,
                    cmd_sasg->amp_mode, cmd_sasg->amp_atten, cmd_sasg->amp_preamp, cmd_sasg->amp_offset,

                    cmd_sasg->trace1_mode, cmd_sasg->trace1_type, cmd_sasg->trace1_detector,
                    cmd_sasg->trace2_mode, cmd_sasg->trace2_type, cmd_sasg->trace2_detector,
                    cmd_sasg->trace3_mode, cmd_sasg->trace3_type, cmd_sasg->trace3_detector,
                    cmd_sasg->trace4_mode, cmd_sasg->trace4_type, cmd_sasg->trace4_detector,

                    cmd_sasg->sweep_time_mode, cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time,
					cmd_sasg->gate_num, cmd_sasg->gate_type, cmd_sasg->gate_delta,
					cmd_sasg->gate_delay, cmd_sasg->gate_length,
#ifndef GATE_SYMB
					cmd_sasg->gate_delay_slot, cmd_sasg->gate_delay_symbol, cmd_sasg->gate_length_slot, cmd_sasg->gate_length_symbol,
#endif
					cmd_sasg->gate_source,
#else
                    cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time, cmd_sasg->gate_delay, cmd_sasg->gate_length, cmd_sasg->gate_source,
#endif
					// measure setup
                    cmd_sasg->avg_hold_mode, cmd_sasg->avg_number, cmd_sasg->sem_meas_type, cmd_sasg->sem_trace_mode, cmd_sasg->sem_trace_type,
                    cmd_sasg->sem_channel_detector, cmd_sasg->sem_offset_detector,
                    // Ref. Channel
                    cmd_sasg->sem_span, cmd_sasg->sem_Integ_BW, cmd_sasg->sem_RBW, cmd_sasg->sem_VBW,
                    // Edit Mask
                    cmd_sasg->sem_Mask_Index[0], cmd_sasg->sem_Mask_Start_Freq[0], cmd_sasg->sem_Mask_Stop_Freq[0], cmd_sasg->sem_Mask_Side[0], cmd_sasg->sem_Mask_RBW[0], cmd_sasg->sem_Mask_VBW[0],
                    cmd_sasg->sem_Mask_Abs_Start_Limit[0], cmd_sasg->sem_Mask_Abs_Stop_Limit[0], cmd_sasg->sem_Mask_Rel_Start_Limit[0], cmd_sasg->sem_Mask_Rel_Stop_Limit[0], cmd_sasg->sem_Mask_Fail_Source[0],

                    cmd_sasg->sem_Mask_Index[1], cmd_sasg->sem_Mask_Start_Freq[1], cmd_sasg->sem_Mask_Stop_Freq[1], cmd_sasg->sem_Mask_Side[1], cmd_sasg->sem_Mask_RBW[1], cmd_sasg->sem_Mask_VBW[1],
                    cmd_sasg->sem_Mask_Abs_Start_Limit[1], cmd_sasg->sem_Mask_Abs_Stop_Limit[1], cmd_sasg->sem_Mask_Rel_Start_Limit[1], cmd_sasg->sem_Mask_Rel_Stop_Limit[1], cmd_sasg->sem_Mask_Fail_Source[1],

                    cmd_sasg->sem_Mask_Index[2], cmd_sasg->sem_Mask_Start_Freq[2], cmd_sasg->sem_Mask_Stop_Freq[2], cmd_sasg->sem_Mask_Side[2], cmd_sasg->sem_Mask_RBW[2], cmd_sasg->sem_Mask_VBW[2],
                    cmd_sasg->sem_Mask_Abs_Start_Limit[2], cmd_sasg->sem_Mask_Abs_Stop_Limit[2], cmd_sasg->sem_Mask_Rel_Start_Limit[2], cmd_sasg->sem_Mask_Rel_Stop_Limit[2], cmd_sasg->sem_Mask_Fail_Source[2],

                    cmd_sasg->sem_Mask_Index[3], cmd_sasg->sem_Mask_Start_Freq[3], cmd_sasg->sem_Mask_Stop_Freq[3], cmd_sasg->sem_Mask_Side[3], cmd_sasg->sem_Mask_RBW[3], cmd_sasg->sem_Mask_VBW[3],
                    cmd_sasg->sem_Mask_Abs_Start_Limit[3], cmd_sasg->sem_Mask_Abs_Stop_Limit[3], cmd_sasg->sem_Mask_Rel_Start_Limit[3], cmd_sasg->sem_Mask_Rel_Stop_Limit[3], cmd_sasg->sem_Mask_Fail_Source[3]
            );

//            cmd_sasg->center_freq = cmd_sasg->center_freq * 1 * 1000;
//            cmd_sasg->span = cmd_sasg->span * 1 * 1000;
            set_SA_params(cmd_sasg);

            /* Ryan Add, to support burst mode when gate view is visible */
            if(cmd_sasg->gate_view) SA_RUN_START_MODE = CMD_GATE_MODE;
            else SA_RUN_START_MODE = MEASURE_DATA_START;
            /* Ryan Add */


            STOP_SA();
//            if (!same_mode) {
                pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
//            }
        }
        else if (cmd_mode == CMD_SA && (TRANSMIT_ON_OFF == measure_type )) { // SET SA PARAMS
/*            bool same_mode = true;
            if(CUR_CMD_MODE != CMD_SA) {
//                init_ad9361_module(1);
                same_mode = false;
            } else {
                if(CUR_CMD_TYPE != measure_type) {
                    same_mode = false;
                }
            }*/
            CUR_CMD_MODE = CMD_SA;
            CUR_CMD_TYPE = measure_type;


            //           mode type d.p. cf sp rbw  vbw  mod  att  t1_m t1_t t1_d t2_m t2_t t2_d t3_m t3_t t3_d t4_m t4_t t4_d mod  t  m    n    o   x   i

            // 0x04 0x00
            // 230000 380000
            // 1000 1000 0x00 20 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 1 5000 1 100 0 0 0
            // 0x04 0x00 230000 380000 1000 1000 0 20 0 0 0 0 0 0 0 0 0 0 0 0 1 5000 1 100 0 0 0

            sscanf(mesg,
                "%hx %hx "
                "%llu %llu "
                "%hu %hu "
                "%hu %hu %hu %hu "

                "%hu %hu %hu "
                "%hu %hu %hu "
                "%hu %hu %hu "
                "%hu %hu %hu "

                "%hu %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                "%hu %hu %d "
                "%hu %hu %d "
                "%d %d "
#ifndef GATE_SYMB
                "%hu %hu %hu %hu "
#endif
                "%d "
#else
                "%hu %hu %d %d %d %d "
#endif

                "%hu %hu %hu %hu %hu %hu %hu" // Transmit
                ,
                &cmd_sasg->code,        &cmd_sasg->meas_type,
                &cmd_sasg->center_freq, &cmd_sasg->span,
                &cmd_sasg->rbw,         &cmd_sasg->vbw,
                &cmd_sasg->amp_mode, &cmd_sasg->amp_atten, &cmd_sasg->amp_preamp, &cmd_sasg->amp_offset,

                &cmd_sasg->trace1_mode, &cmd_sasg->trace1_type, &cmd_sasg->trace1_detector,
                &cmd_sasg->trace2_mode, &cmd_sasg->trace2_type, &cmd_sasg->trace2_detector,
                &cmd_sasg->trace3_mode, &cmd_sasg->trace3_type, &cmd_sasg->trace3_detector,
                &cmd_sasg->trace4_mode, &cmd_sasg->trace4_type, &cmd_sasg->trace4_detector,

                &cmd_sasg->sweep_time_mode, &cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
				&cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time,
				&cmd_sasg->gate_num, &cmd_sasg->gate_type, &cmd_sasg->gate_delta,
				&cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
				&cmd_sasg->gate_delay_slot, &cmd_sasg->gate_delay_symbol, &cmd_sasg->gate_length_slot, &cmd_sasg->gate_length_symbol,
#endif
				&cmd_sasg->gate_source,
#else
                &cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time, &cmd_sasg->gate_delay, &cmd_sasg->gate_length, &cmd_sasg->gate_source,
#endif
                &cmd_sasg->ramp_up_start_time, &cmd_sasg->ramp_up_stop_time, &cmd_sasg->ramp_down_start_time, &cmd_sasg->ramp_down_stop_time,
                &cmd_sasg->lim_off_power, &cmd_sasg->lim_ramp_up_time, &cmd_sasg->lim_ramp_down_time
            );

            dev_printf(
                "0x%02x 0x%02x\n"     // 2
                "%llu %llu\n"         // 2
                "%d %d\n"             // 2
                "%d %d %d %d\n"       // 4

                "%d %d %d\n"          // 3
                "%d %d %d\n"
                "%d %d %d\n"
                "%d %d %d\n"

                "%d %d \n"            // 2
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
                "%d %d %d \n"
                "%d %d %d \n"
                "%d %d \n"
#ifndef GATE_SYMB
                "%d %d %d %d \n"
#endif
                "%d \n"
#else
                "%d %d %d %d %d %d\n" // 6
#endif
                "%d %d %d %d %d %d %d\n" // Transmit
                ,
                cmd_sasg->code, cmd_sasg->meas_type,
                cmd_sasg->center_freq, cmd_sasg->span,
                cmd_sasg->rbw, cmd_sasg->vbw,
                cmd_sasg->amp_mode, cmd_sasg->amp_atten, cmd_sasg->amp_preamp, cmd_sasg->amp_offset,

                cmd_sasg->trace1_mode, cmd_sasg->trace1_type, cmd_sasg->trace1_detector,
                cmd_sasg->trace2_mode, cmd_sasg->trace2_type, cmd_sasg->trace2_detector,
                cmd_sasg->trace3_mode, cmd_sasg->trace3_type, cmd_sasg->trace3_detector,
                cmd_sasg->trace4_mode, cmd_sasg->trace4_type, cmd_sasg->trace4_detector,

                cmd_sasg->sweep_time_mode, cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
				cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time,
				cmd_sasg->gate_num, cmd_sasg->gate_type, cmd_sasg->gate_delta,
				cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
				cmd_sasg->gate_delay_slot, cmd_sasg->gate_delay_symbol, cmd_sasg->gate_length_slot, cmd_sasg->gate_length_symbol,
#endif
				cmd_sasg->gate_source,
#else
                cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time, cmd_sasg->gate_delay, cmd_sasg->gate_length, cmd_sasg->gate_source,
#endif
                cmd_sasg->ramp_up_start_time, cmd_sasg->ramp_up_stop_time, cmd_sasg->ramp_down_start_time, cmd_sasg->ramp_down_stop_time,
                cmd_sasg->lim_off_power, cmd_sasg->lim_ramp_up_time, cmd_sasg->lim_ramp_down_time
            );

//            cmd_sasg->center_freq = cmd_sasg->center_freq * 1 * 1000; // * 100
//            cmd_sasg->span = cmd_sasg->span * 1 * 1000;

            set_SA_params(cmd_sasg);
            STOP_SA();
//            if (!same_mode) {
                pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
//            }

        }
        else if (cmd_mode == CMD_SA && measure_type == SPURIOUS_EMISSION) { // SET SA PARAMS

            CUR_CMD_MODE = CMD_SA;
            CUR_CMD_TYPE = SPURIOUS_EMISSION;
            dev_printf("CMD_SA --> SPRUIOUS_EMISSION\n");

            sscanf(mesg,
                    "%hx %hx "
                    "%llu %llu "
                    "%hu %hu "
                    "%hu %hu %hu %hu "

                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "
                    "%hu %hu %hu "

                    "%hu %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
            		"%hu %hu %d "
            		"%hu %hu %d "
            		"%d %d "
#ifndef GATE_SYMB
            		"%hu %hu %hu %hu "
#endif
            		"%d "
#else
            		"%hu %hu %d %d %d %d "
#endif
                   // measure setup
                    "%d %d %llu %llu "
                    // Band Setup [6]
                    "%d %llu %llu %hu %hu %hd %hd "
                    "%d %llu %llu %hu %hu %hd %hd "
                    "%d %llu %llu %hu %hu %hd %hd "
                    "%d %llu %llu %hu %hu %hd %hd "
                    "%d %llu %llu %hu %hu %hd %hd "
                    "%d %llu %llu %hu %hu %hd %hd "
                    ,
                    &cmd_sasg->code, &cmd_sasg->meas_type,
                    &cmd_sasg->center_freq, &cmd_sasg->span,
                    &cmd_sasg->rbw, &cmd_sasg->vbw,
                    &cmd_sasg->amp_mode, &cmd_sasg->amp_atten, &cmd_sasg->amp_preamp, &cmd_sasg->amp_offset,

                    &cmd_sasg->trace1_mode, &cmd_sasg->trace1_type, &cmd_sasg->trace1_detector,
                    &cmd_sasg->trace2_mode, &cmd_sasg->trace2_type, &cmd_sasg->trace2_detector,
                    &cmd_sasg->trace3_mode, &cmd_sasg->trace3_type, &cmd_sasg->trace3_detector,
                    &cmd_sasg->trace4_mode, &cmd_sasg->trace4_type, &cmd_sasg->trace4_detector,

                    &cmd_sasg->sweep_time_mode, &cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					&cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time,
					&cmd_sasg->gate_num, &cmd_sasg->gate_type, &cmd_sasg->gate_delta,
					&cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
					&cmd_sasg->gate_delay_slot, &cmd_sasg->gate_delay_symbol, &cmd_sasg->gate_length_slot, &cmd_sasg->gate_length_symbol,
#endif
					&cmd_sasg->gate_source,
#else
					&cmd_sasg->gate_mode, &cmd_sasg->gate_view, &cmd_sasg->gate_view_sweep_time, &cmd_sasg->gate_delay, &cmd_sasg->gate_length, &cmd_sasg->gate_source,
#endif
                    // measure setup
                    &cmd_sasg->avg_hold_mode, &cmd_sasg->avg_number, &cmd_sasg->spuem_low_freq, &cmd_sasg->spuem_high_freq,
                    // Band Setup
                    &cmd_sasg->spuem_FRT_Index[0], &cmd_sasg->spuem_FRT_Start_Freq[0], &cmd_sasg->spuem_FRT_Stop_Freq[0], &cmd_sasg->spuem_FRT_RBW[0], &cmd_sasg->spuem_FRT_VBW[0], &cmd_sasg->spuem_FRT_Abs_Start_Limit[0], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[0],
					&cmd_sasg->spuem_FRT_Index[1], &cmd_sasg->spuem_FRT_Start_Freq[1], &cmd_sasg->spuem_FRT_Stop_Freq[1], &cmd_sasg->spuem_FRT_RBW[1], &cmd_sasg->spuem_FRT_VBW[1], &cmd_sasg->spuem_FRT_Abs_Start_Limit[1], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[1],
					&cmd_sasg->spuem_FRT_Index[2], &cmd_sasg->spuem_FRT_Start_Freq[2], &cmd_sasg->spuem_FRT_Stop_Freq[2], &cmd_sasg->spuem_FRT_RBW[2], &cmd_sasg->spuem_FRT_VBW[2], &cmd_sasg->spuem_FRT_Abs_Start_Limit[2], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[2],
					&cmd_sasg->spuem_FRT_Index[3], &cmd_sasg->spuem_FRT_Start_Freq[3], &cmd_sasg->spuem_FRT_Stop_Freq[3], &cmd_sasg->spuem_FRT_RBW[3], &cmd_sasg->spuem_FRT_VBW[3], &cmd_sasg->spuem_FRT_Abs_Start_Limit[3], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[3],
					&cmd_sasg->spuem_FRT_Index[4], &cmd_sasg->spuem_FRT_Start_Freq[4], &cmd_sasg->spuem_FRT_Stop_Freq[4], &cmd_sasg->spuem_FRT_RBW[4], &cmd_sasg->spuem_FRT_VBW[4], &cmd_sasg->spuem_FRT_Abs_Start_Limit[4], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[4],
					&cmd_sasg->spuem_FRT_Index[5], &cmd_sasg->spuem_FRT_Start_Freq[5], &cmd_sasg->spuem_FRT_Stop_Freq[5], &cmd_sasg->spuem_FRT_RBW[5], &cmd_sasg->spuem_FRT_VBW[5], &cmd_sasg->spuem_FRT_Abs_Start_Limit[5], &cmd_sasg->spuem_FRT_Abs_Stop_Limit[5]
                    );

            dev_printf(
                    "%x %x "
                    "%llu %llu "
                    "%d %d "
                    "%d %d %d %d "

                    "%d %d %d "
                    "%d %d %d "
                    "%d %d %d "
                    "%d %d %d "

                    "%d %d "
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
            		"%hu %hu %d "
            		"%hu %hu %d "
            		"%d %d "
#ifndef GATE_SYMB
            		"%hu %hu %hu %hu "
#endif
            		"%d "
#else
            		"%hu %hu %d %d %d %d "
#endif
                    // measure setup
                    "%d %d %llu %llu "
                    // Band Setup [6]
                    "%d %llu %llu %d %d %d %d "
                    "%d %llu %llu %d %d %d %d "
                    "%d %llu %llu %d %d %d %d "
                    "%d %llu %llu %d %d %d %d "
                    "%d %llu %llu %d %d %d %d "
                    "%d %llu %llu %d %d %d %d \n"
                    ,
                    cmd_sasg->code, cmd_sasg->meas_type,
                    cmd_sasg->center_freq, cmd_sasg->span,
                    cmd_sasg->rbw, cmd_sasg->vbw,
                    cmd_sasg->amp_mode, cmd_sasg->amp_atten, cmd_sasg->amp_preamp, cmd_sasg->amp_offset,

                    cmd_sasg->trace1_mode, cmd_sasg->trace1_type, cmd_sasg->trace1_detector,
                    cmd_sasg->trace2_mode, cmd_sasg->trace2_type, cmd_sasg->trace2_detector,
                    cmd_sasg->trace3_mode, cmd_sasg->trace3_type, cmd_sasg->trace3_detector,
                    cmd_sasg->trace4_mode, cmd_sasg->trace4_type, cmd_sasg->trace4_detector,

                    cmd_sasg->sweep_time_mode, cmd_sasg->sweep_time,
#ifdef MQTT_DEF_SUPPORT_NUM_OF_GATE  //Ryan Add , to support number of gate
					cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time,
					cmd_sasg->gate_num, cmd_sasg->gate_type, cmd_sasg->gate_delta,
					cmd_sasg->gate_delay, &cmd_sasg->gate_length,
#ifndef GATE_SYMB
					cmd_sasg->gate_delay_slot, cmd_sasg->gate_delay_symbol, cmd_sasg->gate_length_slot, cmd_sasg->gate_length_symbol,
#endif
					cmd_sasg->gate_source,
#else
					cmd_sasg->gate_mode, cmd_sasg->gate_view, cmd_sasg->gate_view_sweep_time, cmd_sasg->gate_delay, cmd_sasg->gate_length, cmd_sasg->gate_source,
#endif
                    // measure setup
                    cmd_sasg->avg_hold_mode, cmd_sasg->avg_number, cmd_sasg->spuem_low_freq, cmd_sasg->spuem_high_freq,
                    // Band Setup
					cmd_sasg->spuem_FRT_Index[0], cmd_sasg->spuem_FRT_Start_Freq[0], cmd_sasg->spuem_FRT_Stop_Freq[0], cmd_sasg->spuem_FRT_RBW[0], cmd_sasg->spuem_FRT_VBW[0], cmd_sasg->spuem_FRT_Abs_Start_Limit[0], cmd_sasg->spuem_FRT_Abs_Stop_Limit[0],
					cmd_sasg->spuem_FRT_Index[1], cmd_sasg->spuem_FRT_Start_Freq[1], cmd_sasg->spuem_FRT_Stop_Freq[1], cmd_sasg->spuem_FRT_RBW[1], cmd_sasg->spuem_FRT_VBW[1], cmd_sasg->spuem_FRT_Abs_Start_Limit[1], cmd_sasg->spuem_FRT_Abs_Stop_Limit[1],
					cmd_sasg->spuem_FRT_Index[2], cmd_sasg->spuem_FRT_Start_Freq[2], cmd_sasg->spuem_FRT_Stop_Freq[2], cmd_sasg->spuem_FRT_RBW[2], cmd_sasg->spuem_FRT_VBW[2], cmd_sasg->spuem_FRT_Abs_Start_Limit[2], cmd_sasg->spuem_FRT_Abs_Stop_Limit[2],
					cmd_sasg->spuem_FRT_Index[3], cmd_sasg->spuem_FRT_Start_Freq[3], cmd_sasg->spuem_FRT_Stop_Freq[3], cmd_sasg->spuem_FRT_RBW[3], cmd_sasg->spuem_FRT_VBW[3], cmd_sasg->spuem_FRT_Abs_Start_Limit[3], cmd_sasg->spuem_FRT_Abs_Stop_Limit[3],
					cmd_sasg->spuem_FRT_Index[4], cmd_sasg->spuem_FRT_Start_Freq[4], cmd_sasg->spuem_FRT_Stop_Freq[4], cmd_sasg->spuem_FRT_RBW[4], cmd_sasg->spuem_FRT_VBW[4], cmd_sasg->spuem_FRT_Abs_Start_Limit[4], cmd_sasg->spuem_FRT_Abs_Stop_Limit[4],
					cmd_sasg->spuem_FRT_Index[5], cmd_sasg->spuem_FRT_Start_Freq[5], cmd_sasg->spuem_FRT_Stop_Freq[5], cmd_sasg->spuem_FRT_RBW[5], cmd_sasg->spuem_FRT_VBW[5], cmd_sasg->spuem_FRT_Abs_Start_Limit[5], cmd_sasg->spuem_FRT_Abs_Stop_Limit[5]
                    );

            set_SA_params(cmd_sasg);

            STOP_SA(); 
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
        }
        else if (cmd_mode == CMD_SA && measure_type == CAL_SA) { // SA CALIBRATION File Transfer
            int dummy;
            int cal_cmd = 0;
//            int cal_arg = 0;
            char cal_arg_str[128] = {0};
            int len = sscanf(mesg, "%x %x %x %s", &dummy, &dummy, &cal_cmd, cal_arg_str);
            dev_printf("command words %d : 0x%02x %s\n", len, cal_cmd, cal_arg_str);

            calibration_sa(cal_cmd, cal_arg_str);
        }
        else if (cmd_mode == CMD_IQ_IM_CAL) { // IQ Calibration imbalance
            // Set FPGA Register related Calibration Block
            dev_printf("CMD_IQ_IM_CAL\n");
            sscanf(mesg, "%hx %lld %hu %hu %hu %lld %d %d ",
                    &cmd_iqcal->meas_mode,
                    &cmd_iqcal->center_freq,
                    &cmd_iqcal->amp_mode, &cmd_iqcal->amp_atten, &cmd_iqcal->amp_preamp,
                    &cmd_iqcal->freq_offset,
                    &cmd_iqcal->carrier_threshold, &cmd_iqcal->image_threashold);

            dev_printf("test %x %lld %d %d %d %lld %d %d\n",
                    cmd_iqcal->meas_mode,
                    cmd_iqcal->center_freq,
                    cmd_iqcal->amp_mode, cmd_iqcal->amp_atten, cmd_iqcal->amp_preamp,
                    cmd_iqcal->freq_offset,
                    cmd_iqcal->carrier_threshold, cmd_iqcal->image_threashold);
            sa_IQ_imbalance_cal(cmd_iqcal);
        }
/*        else if (cmd_mode == CMD_MODE_ACCURACY && measure_type == 0x9999991) { // SET 5G PARAMS
            CUR_CMD_MODE = CMD_MODE_ACCURACY;
            CUR_CMD_TYPE = TYPE_5G_DEMOD;
//            init_ad9361_module(2);

            ds_NR_SetAPI* params = get_dl_demod_params();
            uint64_t freq = 0;
            sscanf(mesg, "%x %x %llu %x %d %d %x %d %x %d %d %d",
                            &dummy1,
                            &dummy2,
                            &freq,
                            &atten_mode,
                            &atten_val,
                            &atten_offset,
                            &preamp,
                            &params->profile_type,
                            &params->SSBInfo.SSB_Config_type,
                            &params->SSBInfo.RB_Offset,
                            &params->SSBInfo.k_SSB,
                            &params->LimitInfo.freq_offset);
            params->fc = freq * 10 * 1000; // from app, in order to make int, it comes with 100 times number

            dev_printf("%x %x %llu %x %d %d %x %d %x %d %d %d",
                            dummy1,
                            dummy2,
                            params->fc,
                            atten_mode,
                            atten_val,
                            atten_offset,
                            preamp,
                            params->profile_type,
                            params->SSBInfo.SSB_Config_type,
                            params->SSBInfo.RB_Offset,
                            params->SSBInfo.k_SSB,
                            params->LimitInfo.freq_offset);

            dev_printf("\nSetting 5G NR\n");
            set_dl_demod_params(atten_mode, atten_val, atten_offset, preamp);
            if (atten_mode == 1) {
                get_auto_atten_5G(&auto_att, &preamp_state);
                sprintf(mqtt_mesg, "0x24 %d %d", auto_att, preamp_state);
                pubMqttString(mqtt_mesg, strlen(mqtt_mesg));
            } else {
                pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
            }

        }*/
        else if (cmd_mode == CMD_MODE_ACCURACY &&
                        (measure_type == TYPE_5G_DEMOD || measure_type == TYPE_TAE)) { // SET 5G PARAMS
            CUR_CMD_MODE = CMD_MODE_ACCURACY;
            CUR_CMD_TYPE = measure_type;
            ds_NR_SetAPI* params = get_dl_demod_params();
            uint64_t freq = 0;

            sscanf(mesg, "%x %x %llu %x %d %d %x %d %x %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %llu %llu %llu %llu %d %d %d %d"
#ifdef NR_NEW_FEATURE
                            "%d %d"
#endif
                            ,
                            &dummy1,
                            &dummy2,
                            &freq,
                            &atten_mode,
                            &atten_val,
                            &atten_offset,
                            &preamp,
                            &params->profile_type,
                            &params->SSBInfo.SSB_Config_type,
                            &params->SSBInfo.RB_Offset,
                            &params->SSBInfo.k_SSB,
                            &params->LimitInfo.freq_offset,
                            &params->LimitInfo.evm,
                            &params->LimitInfo.TAE,
                            &params->LimitInfo.Inter_TAE,
                            &params->trigger_source,
                            &params->TAEInfo.TAE_Meas,
                            &params->TAEInfo.TAE_Type,
                            &params->TAEInfo.Meas_Cnt,
                            &params->TAEInfo.Num_of_Tx_Ant,
                            &params->TAEInfo.Carr_Stats[0], // carrier N on/off
                            &params->TAEInfo.Carr_Stats[1],
                            &params->TAEInfo.Carr_Stats[2],
                            &params->TAEInfo.Carr_Stats[3],
                            &params->TAEInfo.Freq_of_Carr[0],
                            &params->TAEInfo.Freq_of_Carr[1],
                            &params->TAEInfo.Freq_of_Carr[2],
                            &params->TAEInfo.Freq_of_Carr[3],
                            &params->TAEInfo.profile_type[0],
                            &params->TAEInfo.profile_type[1],
                            &params->TAEInfo.profile_type[2],
                            &params->TAEInfo.profile_type[3]
#ifdef NR_NEW_FEATURE
                             ,
                             &params->duplex_type,
                             &params->SCS
#endif
                            );

/*            sscanf(mesg, "%x %x %llu %x %d %d %x %d %x %d %d %d %d %d %d %d %d %d %d %d %llu %llu %llu %llu",
                             &dummy1,
                             &dummy2,
                             &freq,
                             &atten_mode,
                             &atten_val,
                             &atten_offset,
                             &preamp,
                             &params->profile_type,
                             &params->SSBInfo.SSB_Config_type,
                             &params->SSBInfo.RB_Offset,
                             &params->SSBInfo.k_SSB,
                             &params->LimitInfo.freq_offset,
                             &params->LimitInfo.evm,
                             &params->LimitInfo.TAE,
                             &params->trigger_source,
                             &params->TAEInfo.TAE_Meas,
                             &params->TAEInfo.TAE_Type,
                             &params->TAEInfo.Meas_Cnt,
                             &params->TAEInfo.Num_of_Tx_Ant,
                             &params->TAEInfo.Inter_Num_of_Carr,
                             &params->TAEInfo.Freq_of_Carr[0],
                             &params->TAEInfo.Freq_of_Carr[1],
                             &params->TAEInfo.Freq_of_Carr[2],
                             &params->TAEInfo.Freq_of_Carr[3]
                             );*/

//            params->fc = freq * 1 * 1000; // from app, in order to make int, it comes with 100 times number
            params->fc = freq;
//                  0x42 0x07 365001 0x01 20 0 0x00
            dev_printf("0x%0x 0x%02x %llu 0x%02x %d %d 0x%02x %d 0x%02x %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %llu %llu %llu %llu %d %d %d %d"
#ifdef NR_NEW_FEATURE
                            " %d %d\n"
#endif
                            ,
                            dummy1,
                            dummy2,
                            freq,
                            atten_mode,
                            atten_val,
                            atten_offset,
                            preamp,
                            params->profile_type,
                            params->SSBInfo.SSB_Config_type,
                            params->SSBInfo.RB_Offset,
                            params->SSBInfo.k_SSB,
                            params->LimitInfo.freq_offset,
                            params->LimitInfo.evm,
                            params->LimitInfo.TAE,
                            params->LimitInfo.Inter_TAE,
                            params->trigger_source,
                            params->TAEInfo.TAE_Meas,
                            params->TAEInfo.TAE_Type,
                            params->TAEInfo.Meas_Cnt,
                            params->TAEInfo.Num_of_Tx_Ant,
                            params->TAEInfo.Carr_Stats[0], // carrier N on/off
                            params->TAEInfo.Carr_Stats[1],
                            params->TAEInfo.Carr_Stats[2],
                            params->TAEInfo.Carr_Stats[3],
//                            &params->TAEInfo.Inter_Num_of_Carr,
                            params->TAEInfo.Freq_of_Carr[0],
                            params->TAEInfo.Freq_of_Carr[1],
                            params->TAEInfo.Freq_of_Carr[2],
                            params->TAEInfo.Freq_of_Carr[3],
                            params->TAEInfo.profile_type[0],
                            params->TAEInfo.profile_type[1],
                            params->TAEInfo.profile_type[2],
                            params->TAEInfo.profile_type[3]
#ifdef NR_NEW_FEATURE
                            ,
                            params->duplex_type,
                            params->SCS
#endif
                            );

            dev_printf("\nSetting 5G NR / TAE\n");
            if (params->TAEInfo.TAE_Meas == 0) {
                set_TAE_mode(0);
            }
            is_TAE_mode();

            // 20240123 JBK : Add Correlator =>
            nr5G_corr_blk_cntrl(params->SCS);
            set_nr_param_change(0);
            // 20240123 JBK : Add Correlator <=
            set_dl_demod_params(atten_mode, atten_val, atten_offset, preamp);
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));

        }
        else if (cmd_mode == CMD_MODE_ACCURACY && measure_type == TYPE_5G_NR_SCAN) { // SET 5G NR_SCAN PARAMS
            CUR_CMD_MODE = CMD_MODE_ACCURACY;
            CUR_CMD_TYPE = measure_type;
            ds_NR_Scan_SetAPI* params = get_dl_scan_params();

            sscanf(mesg, "%x %x %d %llu %d %d %llu %d %d %llu %d %d %llu %d %d"
#ifdef NR_NEW_FEATURE
                            "%d %d %d %d %d %d %d %d %d"
#endif
                            ,
                            &dummy1,
                            &dummy2,
                            &params->Carriers.Carrier_State[0],
							&params->Carriers.Freq_of_Carr[0],
							&params->Carriers.profile_type[0],
                            &params->Carriers.Carrier_State[1],
							&params->Carriers.Freq_of_Carr[1],
							&params->Carriers.profile_type[1],
                            &params->Carriers.Carrier_State[2],
							&params->Carriers.Freq_of_Carr[2],
							&params->Carriers.profile_type[2],
							&params->Carriers.Carrier_State[3],
							&params->Carriers.Freq_of_Carr[3],
							&params->Carriers.profile_type[3],
							&params->Amp_Offset
#ifdef NR_NEW_FEATURE
							,
							&params->Carriers.duplex[0],
							&params->Carriers.duplex[1],
							&params->Carriers.duplex[2],
							&params->Carriers.duplex[3],
							&params->Carriers.SCS[0],
							&params->Carriers.SCS[1],
							&params->Carriers.SCS[2],
							&params->Carriers.SCS[3],
							&params->trigger_source
#endif
                            );

            dev_printf("0x%x 0x%x %d %llu %d %d %llu %d %d %llu %d %d %llu %d %d\n"
#ifdef NR_NEW_FEATURE
                            "%d %d %d %d %d %d %d %d %d\n"
#endif
                            ,
                            dummy1,
                            dummy2,
                            params->Carriers.Carrier_State[0],
							params->Carriers.Freq_of_Carr[0],
							params->Carriers.profile_type[0],
                            params->Carriers.Carrier_State[1],
							params->Carriers.Freq_of_Carr[1],
							params->Carriers.profile_type[1],
                            params->Carriers.Carrier_State[2],
							params->Carriers.Freq_of_Carr[2],
							params->Carriers.profile_type[2],
							params->Carriers.Carrier_State[3],
							params->Carriers.Freq_of_Carr[3],
							params->Carriers.profile_type[3],
							params->Amp_Offset
#ifdef NR_NEW_FEATURE
							,
							params->Carriers.duplex[0],
							params->Carriers.duplex[1],
							params->Carriers.duplex[2],
							params->Carriers.duplex[3],
							params->Carriers.SCS[0],
							params->Carriers.SCS[1],
							params->Carriers.SCS[2],
							params->Carriers.SCS[3],
							params->trigger_source
#endif
                            );

            dev_printf("\nSetting 5G NR SCAN\n");
            set_SCAN_mode(1);
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));

            // 20240131 JBK : Add Correlator =>
            for (int n = 0; n < 4; n++)
                set_nr_param_change(n);
            // 20240131 JBK : Add Correlator <=
        }
        else if (cmd_mode == CMD_MODE_ACCURACY && measure_type == TYPE_LTE_FDD) { // SET LTE PARAMS
            CUR_CMD_MODE = CMD_MODE_ACCURACY;
            CUR_CMD_TYPE = TYPE_LTE_FDD;

            dsLte_UserInput_Param* params = get_LTE_params();
            uint64_t freq = 0;
            sscanf(mesg, "%x %x %llu %x %d %d %x %d %x %d %d %d",
                            &dummy1,
                            &dummy2,
                            &freq,
                            &atten_mode,
                            &atten_val,
                            &atten_offset,
                            &preamp,
                            &params->profile_type,
                            &params->freq_offset,
                            &params->min_RS_EVM,
                            &params->TAE,
                            &params->trigger_source
                            );
//            params->fc = freq * 1 * 1000; // from app, in order to make int, it comes with 100 times number
            params->fc = freq;

            dev_printf("%x %x %llu %x %d %d %x %d %x %d %d %d %d",
                            dummy1,
                            dummy2,
                            params->fc,
                            atten_mode,
                            atten_val,
                            atten_offset,
                            preamp,
                            params->profile_type,
                            params->freq_offset,
                            params->min_RS_EVM,
                            params->TAE,
                            params->trigger_source
                            );

            dev_printf("\nSetting LTD FDD\n");
            // 20240213 JBK : Add correlator =>
            lte_filter_blk_cntrl(params->profile_type);
            // 20240213 JBK : Add correlator <=
            set_LTE_params(atten_mode, atten_val, atten_offset, preamp);
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
        }
        /* <-- Ryan Add@2023.12.06, to support LTE TDD */
        else if (cmd_mode == CMD_MODE_ACCURACY && measure_type == TYPE_LTE_TDD) { // SET LTE PARAMS
            CUR_CMD_MODE = CMD_MODE_ACCURACY;
            CUR_CMD_TYPE = TYPE_LTE_TDD;

            dsLte_UserInput_Param* params = get_LTE_params();
            uint64_t freq = 0;
            sscanf(mesg, "%x %x %llu %x %d %d %x %d %x %d %d %d %d %d",
                            &dummy1,
                            &dummy2,
                            &freq,
                            &atten_mode,
                            &atten_val,
                            &atten_offset,
                            &preamp,
                            &params->profile_type,
                            &params->freq_offset,
                            &params->min_RS_EVM,
                            &params->TAE,
                            &params->trigger_source,
							&params->DLUL_config_index,
							&params->subframe_config_index
                            );
            params->fc = freq;

            printf("%x %x %llu %x %d %d %x %d %x %d %d %d %d %d",
                            dummy1,
                            dummy2,
                            params->fc,
                            atten_mode,
                            atten_val,
                            atten_offset,
                            preamp,
                            params->profile_type,
                            params->freq_offset,
                            params->min_RS_EVM,
                            params->TAE,
                            params->trigger_source,
							params->DLUL_config_index,
							params->subframe_config_index
                            );

            printf("\nSetting LTD TDD\n");
            // 20240213 JBK : Add correlator =>
            lte_filter_blk_cntrl(params->profile_type);
            // 20240213 JBK : Add correlator <=
            set_LTE_TDD_params(atten_mode, atten_val, atten_offset, preamp, params->DLUL_config_index, params->subframe_config_index);
            pubMqttString(CMD_RESPONSE, strlen(CMD_RESPONSE));
        }
        /* Ryan Add -->*/
        /* Ryan Add, to add settings for SG functionality */
#ifdef SG_DEF_SG_ENABLED
        else if (cmd_mode == CMD_SG)
        {
			dev_printf("mesg: %s \n", mesg);
			CUR_CMD_MODE = CMD_SG;

        	switch (measure_type)
        	{

				case 0x01:
				{

					dev_printf("Set Params for SG \n");

					sscanf(mesg, "%x %x %llu %d %u %u %u %f %f %f %f %f",
							&dummy1, &dummy2,
							&sg_param.Freqeuncy, &sg_param.Amplitude, &sg_param.RF, &sg_param.Mod,
							&sg_param.Calibration,
							&sg_param.I_Gain, &sg_param.Q_Gain, &sg_param.Phase_Skew, &sg_param.I_Offset, &sg_param.Q_Offset);

					sg_param.I_Gain = (double)sg_param.I_Gain/100000;
					sg_param.Q_Gain = (double)sg_param.Q_Gain/100000;
					sg_param.Phase_Skew = (double)sg_param.Phase_Skew/100;
					sg_param.I_Offset = (double)sg_param.I_Offset/100;
					sg_param.Q_Offset = (double)sg_param.Q_Gain/100;


					dev_printf("%llu %d %u %u %u %f %f %f %f %f\n",
							sg_param.Freqeuncy, sg_param.Amplitude, sg_param.RF, sg_param.Mod,
							sg_param.Calibration,
							sg_param.I_Gain, sg_param.Q_Gain, sg_param.Phase_Skew, sg_param.I_Offset, sg_param.Q_Offset);


					sg_set_param(&sg_param);

					break;
				}
				case 0x02:
				{
					char filename[256] = "";
					char fullpath[256] = "";
					dev_printf("Set SG file to transmit!\n");
					sscanf(mesg,"%x %x %s", &dummy1, &dummy2, filename);
					sprintf(fullpath,"%s/%s",MQTT_DEF_DEFAULT_FTP_PATH,filename);
					dev_printf("SG file: %s\n",fullpath);

					sg_set_source(fullpath);
					break;
				}
				default:
					break;
    	    }

        }
        /* Ryan Add */
#endif
        /* Ryan Add, GPS information request/response */
        else if (cmd_mode == CMD_GPS_INFO_REQ)
        {
        	dev_printf("GSP info request from APP\n");
        	dev_printf("GSP info palyload size: %d\n", sizeof(gps_info));
        	gps_info.resp_command = 0x53;
        	hexDump(&gps_info,sizeof(GPS_INFO));
            pubMqttDataByteArray(&gps_info, sizeof(GPS_INFO));
        }
        /* Ryan Add */
        /* Ryan Add, GPS Holdover Configuration Request */
        else if (cmd_mode == CMD_GPS_HO_REQ)
        {
        	dev_printf("GSP Holdover Configuration from APP\n");
        	ho_control_set_param(mesg);
        	char *msg = CMD_GPS_HO_RESP" 0" ;
            pubMqttString(msg, strlen(msg));
        }
        /* wooyo Add*/
        else if (cmd_mode == CMD_RTK_GPS_REQ)
        {
        	rtk_gps_send_mqtt_once();
        }
        else if (cmd_mode == CMD_RTK_GPS_START_STOP) {
            uint32_t cmd_mode = 0;
            uint32_t rtk_thread_status = 0;
            sscanf(mesg, "%x %d", &cmd_mode, &rtk_thread_status);

            if (rtk_thread_status > 0)
            {
            	if (rtk_gps_start_thread(500) == 0) {
            		printf("RTK GPS monitoring started\n");
            	}
            }
            else
            {
            	rtk_gps_stop_thread();
        		printf("RTK GPS monitoring stopped\n");
            }

        }
        /* UDP IQ Stream Control - Direct DMA Capture and Transmission */
        else if (cmd_mode == CMD_UDP_IQ_CTRL) {
            static uint64_t last_configured_freq = 0; // Remember last configured frequency
            uint32_t dummy = 0;
            uint32_t sample_count = 0;
            uint32_t capture_mode = 4; // Default: CIC Output
            uint64_t frequency_khz = 2000000; // Default: 2 GHz
            int scanned = 0;

            // Try to parse: 0x93 <sample_count> [mode] [frequency_khz]
            scanned = sscanf(mesg, "%x %u %u %llu", &dummy, &sample_count, &capture_mode, &frequency_khz);
            if (scanned < 2) {
                dev_printf("UDP IQ: Invalid parameters\n");
                char resp_msg[64];
                sprintf(resp_msg, CMD_UDP_IQ_RESP" 0 ERROR");
                pubMqttString(resp_msg, strlen(resp_msg));
                goto SKIP_UDP_IQ_CTRL;
            }

            printf("UDP IQ Capture Request: samples=%u, mode=%u, freq=%llu kHz\n",
                  sample_count, capture_mode, frequency_khz);

#ifdef UDP_IQ_STREAM_ENABLED
            // Configure RF settings only if frequency changed
            if (frequency_khz != last_configured_freq) {
                dev_printf("UDP IQ: Configuring RF - Frequency=%llu kHz (changed from %llu kHz)\n",
                          frequency_khz, last_configured_freq);

                // Set AD9361 frequency
                set_ad9361_freqeuncy(frequency_khz);

                // Set RX gain based on frequency (automatic gain control)
                sa_set_ad9361_rx_gain(frequency_khz);

                // Set RF band control
                set_RF_BAND_CTRL(frequency_khz);

                // Small delay to allow RF settings to stabilize
                usleep(10000); // 10ms

                // Update last configured frequency
                last_configured_freq = frequency_khz;

                dev_printf("UDP IQ: RF configuration complete\n");
            } else {
                dev_printf("UDP IQ: Reusing RF configuration (freq=%llu kHz unchanged)\n", frequency_khz);
            }

            // DMA capture parameters
            int32_t dma_addr = 0x30000000;  // Fixed DMA address
            int32_t capture_bytes = sample_count << 2;  // samples * 4 bytes (16-bit I + 16-bit Q)

            // Perform direct FPGA DMA capture
            dev_printf("UDP IQ: Starting DMA capture (addr=0x%x, bytes=%d, mode=%u)\n",
                      dma_addr, capture_bytes, capture_mode);

            PL_sa_iq_capt_dma(dma_addr, capture_bytes, capture_mode);

            // Get captured data from DRAM buffer
            uint32_t *dma_buffer = (uint32_t*)get_DRAM_buffer();
            if (dma_buffer == NULL) {
                dev_printf("UDP IQ: Failed to get DRAM buffer\n");
                char resp_msg[64];
                sprintf(resp_msg, CMD_UDP_IQ_RESP" 0 BUFFER_ERROR");
                pubMqttString(resp_msg, strlen(resp_msg));
                goto SKIP_UDP_IQ_CTRL;
            }

            // Send raw IQ data via UDP immediately
            dev_printf("UDP IQ: Sending %u samples via UDP\n", sample_count);
            int packets_sent = udp_iq_send_raw_data(dma_buffer, sample_count);

            if (packets_sent > 0) {
                char resp_msg[64];
                sprintf(resp_msg, CMD_UDP_IQ_RESP" %u %d", sample_count, packets_sent);
                pubMqttString(resp_msg, strlen(resp_msg));
                dev_printf("UDP IQ: Successfully sent %d packets (%u samples)\n", packets_sent, sample_count);
            } else {
                char resp_msg[64];
                sprintf(resp_msg, CMD_UDP_IQ_RESP" 0 SEND_ERROR");
                pubMqttString(resp_msg, strlen(resp_msg));
                dev_printf("UDP IQ: Failed to send data\n");
            }
#else
            char resp_msg[64];
            sprintf(resp_msg, CMD_UDP_IQ_RESP" 0 DISABLED");
            pubMqttString(resp_msg, strlen(resp_msg));
            dev_printf("UDP IQ stream is disabled\n");
#endif

SKIP_UDP_IQ_CTRL:
            ; // Empty statement for label
        }
        /* 61.44MHz Test Mode - AD9361 Clock Test */
        else if (cmd_mode == CMD_61_44_TEST) {
            dev_printf("[MQTT] 61.44MHz Test command received: %s\n", mesg);
            test_6144_mqtt_handler(mesg);
        }
        /* Ryan Add */
        /* Ryan Add, LNA connection status */
        else if(cmd_mode == CMD_LNA_CON)
        {
            uint32_t cmd_mode = 0;
            uint32_t lna_status = 0;
            sscanf(mesg, "%x %d", &cmd_mode, &lna_status);
            sprintf(mqtt_mesg, "0x%02x %d", CMD_LNA_CON, lna_status);
            pubMqttString(mqtt_mesg, strlen(mqtt_mesg));
            printf("LNA %s\n",(lna_status)?"connected":"disconnected");
            // 20220808 JBK : get lna status =>
            get_lna_status_info(lna_status);
            // 20220808 JBK : get lna status <=
        }
        /* Ryan Add*/
        else if (cmd_mode == CMD_FW) {
            uint32_t dummy;
            int arg1 = 0;
            sscanf(mesg, "%x %x", &dummy, &arg1);
            if (arg1 == 0x00) {
                cmd_vswr->code = REQ_FIRMWARE_VER;
            } else if (arg1 == 0x01) {
                cmd_vswr->code = FW_DOWNLOAD_START;
            } else if (arg1 == 0x03) {
                cmd_vswr->code = FW_DOWNLOAD_DONE;
            }
            cmd_vswr->handler(cmd_vswr);
        }



        // Add Factory Cal.
        else if (cmd_mode == CMD_FACTORY_CAL) {

        	// step input 0, 1, 2 to cal step
        	int cal_step = 0;

        	sscanf(mesg, "%x %d", &cmd_vswr->code, &cal_step);

        	if (cal_step < 0 || cal_step > 2)
        	{
            	dev_printf("Invalid cal step %d\n", cal_step);
        	}

        	else
        	{
            	cmd_vswr->cal_type = 2; // factory cal type
            	cmd_vswr->code = CALIBRATION_RUN;
            	cmd_vswr->cal_step = cal_step;

            	dev_printf("VSWR Cal. step is %d\n", cal_step);

                cmd_vswr->handler(cmd_vswr);
        	}

            pubMqttString(mesg, strlen(mesg));
        }

        else if (cmd_mode == CMD_RESET_CAL) {

        	int args = 1;
        	sscanf(mesg, "%x %x ", &cmd_mode, &args);
            printf("Cal Reset Argument = args \n", args);

			rm_cal_file(args);
			set_factory_cal_path(args);

            pubMqttString(mesg, strlen(mesg));
        }



        else { // action trigger command
            cmd_vswr->code = cmd_mode;
            cmd_vswr->handler(cmd_vswr);
        }
    }

EXIT_MQTT_RESP:
    MQTTAsync_freeMessage(&message);
    MQTTAsync_free(topicName);

    return 1;
}

static void __deliveryCompleted(void* context, MQTTAsync_token token)
{
    dev_printf("Delivery completed Token %d\n", token);
}

void onDisconnect(void* context, MQTTAsync_successData* response)
{
    dev_printf("Successful disconnection\n");
    disc_finished = 1;
}

void onSubscribe(void* context, MQTTAsync_successData* response)
{
    dev_printf("Subscribe succeeded\n");
    subscribed = 1;
}

void onSubscribeFailure(void* context, MQTTAsync_failureData* response)
{
    dev_printf("Subscribe failed, rc %d\n", response ? response->code : 0);
    finished = 1;
}

void onConnectFailure(void* context, MQTTAsync_failureData* response)
{
    dev_printf("Connect failed, rc %d\n", response ? response->code : 0);
    finished = 1;
}

void onConnect(void* context, MQTTAsync_successData* response)
{
    MQTTAsync client = (MQTTAsync)context;
    MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;

    dev_printf("Successful connection, then\n");
    dev_printf("Successful connection, then\n");

    dev_printf("Subscribing to topic %s\n\t\t\t\t\t  for client ID %s using QoS%d\n",
    		TOPIC_CMD, CLIENT_ID, QOS);
    opts.onSuccess = onSubscribe;
    opts.onFailure = onSubscribeFailure;
    opts.context = client;

    // Notify Android app READY
    int rc;
    if ((rc = MQTTAsync_subscribe(client, TOPIC_CMD, QOS, &opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start subscribe, return code %d\n", rc);
//        exit(EXIT_FAILURE);
    }


//    if ((rc = MQTTAsync_subscribe(client, TOPIC_DATA1, QOS, &opts)) != MQTTASYNC_SUCCESS) {
//        dev_printf("Failed to start subscribe, return code %d\n", rc);
//        //        exit(EXIT_FAILURE);
//    }


//    if (restart_reason == 1) {
//        pubMqttString("0x200000", strlen("0x200000"));
//        pubMqttEmtptyQueue();
//        pubMqttString("0x66", strlen("0x66"));
//        dev_printf("---------------------------------------------------- suprised \n");
//    } else
        ping_MQTT();
        run_sa_measure_thread(0);
}

void onSend(void* context, MQTTAsync_successData* response)
{
    dev_printf("MQTT onSend message with token value %d\n\n", response->token);
    return;
}

static void __connectionLost(void *context, char *cause)
{
    MQTTAsync client = (MQTTAsync)context;
    MQTTAsync_connectOptions conn_opts = MQTTAsync_connectOptions_initializer;
    int rc;

    dev_printf("\nConnection lost\n");
    dev_printf("     cause: %s\n", cause);
    dev_printf("Reconnecting\n");

    //
//    MQTTAsync_connectOptions conn_opts = MQTTAsync_connectOptions_initializer;
    conn_opts.keepAliveInterval = 60;
    conn_opts.cleansession = 1;
    conn_opts.onSuccess = onConnect;
    conn_opts.onFailure = onConnectFailure;
    conn_opts.context = client;
    //
    if ((rc = MQTTAsync_connect(client, &conn_opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start connect, return code %d\n", rc);
        finished = 1;
    }
}

int pubMqttString(void* data, int len)
{
	dev_printf("%s %s (len : %d)\n",__FUNCTION__, (char*)data, len);
//    MQTTAsync client = (MQTTAsync)context;
    MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
    MQTTAsync_message pubmsg = MQTTAsync_message_initializer;
    int rc;

    opts.onSuccess = onSend;
    opts.context = client;

    pubmsg.payload = data;
    pubmsg.payloadlen = len;
    pubmsg.qos = QOS;
    pubmsg.retained = 0;


    if ((rc = MQTTAsync_sendMessage(client, TOPIC_DATA1, &pubmsg, &opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start sendMessage, return code %d\n", rc);
        return -1;
    }

    return 0;
}

int pubMqttCmd(void* data, int len)
{
	dev_printf("%s %s (len : %d)\n",__FUNCTION__, (char*)data, len);
//    MQTTAsync client = (MQTTAsync)context;
    MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
    MQTTAsync_message pubmsg = MQTTAsync_message_initializer;
    int rc;

    opts.onSuccess = onSend;
    opts.context = client;

    pubmsg.payload = data;
    pubmsg.payloadlen = len;
    pubmsg.qos = QOS;
    pubmsg.retained = 0;


    if ((rc = MQTTAsync_sendMessage(client, TOPIC_CMD, &pubmsg, &opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start sendMessage, return code %d\n", rc);
        return -1;
    }

    return 0;
}

int pubMqttEmtptyQueue()
{
    MQTTAsync_send(client, TOPIC_DATA2, 0, NULL, 1, 1, NULL);
    MQTTAsync_send(client, TOPIC_DATA1, 0, NULL, 1, 1, NULL);
    MQTTAsync_send(client, TOPIC_CMD, 0, NULL, 1, 1, NULL);

    return 0;
}

int pubMqttDataByteArray(int *buffer, int size)  // int
{
	dev_printf("MQTTT Complete : Measured Data size %d will be sent via MQTT\n\n", size);
    MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
    MQTTAsync_message pubmsg = MQTTAsync_message_initializer;
    int rc;

    opts.onSuccess = onSend;
    opts.context = client;

    /*
    pubmsg.payload = "";  //PAYLOAD;
	pubmsg.payloadlen = strlen(pubmsg.payload);
	pubmsg.qos = 1;
	pubmsg.retained = 0;
	MQTTAsync_sendMessage(client, TOPIC_DATA2, &pubmsg, &opts);
    */
    pubmsg.payload  = buffer;
    pubmsg.payloadlen = size;
    pubmsg.qos = QOS;
    pubmsg.retained = 0;

    if ((rc = MQTTAsync_sendMessage(client, TOPIC_DATA2, &pubmsg, &opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start sendMessage, return code %d\n", rc);
        return -1;
    }

    return 0;
}

/*
 * Initialize for Pub/Sub MQTT
 * 	- Entry Point for MQTT
 * 	- Create a client and Try to Connect to the broker
 * 	- when connected successfully, subscription is initiated
 * 	- Set 3 CallBack functions : Losing connection, Message Arrived, Delivery Completed
 */
static int setup_MQTT_Client()
{
    MQTTAsync_create(&client, BROKER_ADDR, CLIENT_ID, MQTTCLIENT_PERSISTENCE_NONE, NULL);
    MQTTAsync_setCallbacks(client, client, __connectionLost, __messageArrived, __deliveryCompleted);

    MQTTAsync_connectOptions conn_opts = MQTTAsync_connectOptions_initializer;
    conn_opts.keepAliveInterval = 60;
    conn_opts.cleansession = 1;
//    conn_opts.maxInflight = 3;
//    conn_opts.automaticReconnect = 1;
    conn_opts.onSuccess = onConnect;
    conn_opts.onFailure = onConnectFailure;
    conn_opts.context = client;

    int rc;
    if ((rc = MQTTAsync_connect(client, &conn_opts)) != MQTTASYNC_SUCCESS) {
        dev_printf("Failed to start connect, return code %d\n", rc);
        exit(EXIT_FAILURE);
    }

    while (!subscribed) usleep(10000);

    /* onConnectFailure / onSubscribeFailure */
    if (finished) goto exit;

    for(;;) {
        usleep(100);
    }

exit:
    MQTTAsync_destroy(&client);

    return rc;
}

void init_Command_MQTT(commands *cmds)
{
	cmd_vswr = cmds->vswr;
	cmd_vswr->start_freq = MIN_FREQ;
	cmd_vswr->stop_freq = MAX_FREQ;
    cmd_sasg = cmds->sasg;
    cmd_iqcal = cmds->iqcal;

    setup_MQTT_Client();
}

void ping_MQTT()
{
    char mqtt_mesg[256];
    int runmode = get_RUN_MODE();
    sprintf(mqtt_mesg, "0x66 %d", runmode);
    pubMqttString(mqtt_mesg, strlen(mqtt_mesg));
}
