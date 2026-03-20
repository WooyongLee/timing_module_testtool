/*
 * init_ad9361.c
 *
 *  Created on: Apr 1, 2019
 *      Author: swdev1
 */

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

// Project Specific
#define DEBUG 1
#define MODULE_NAME "AD9361"
#include <common/debug.h>
#include <common/util.h>
#include <HW/ad9361/ad9361_manager.h>
#include <HW/PL/pl_regs.h>
#include <HW/PL/pl_driver.h>
#include <HW/PL/spi.h>


#include "config.h"
/* Ryan Add, to update gain tables except VSWR (VSWR use its own gain table */
const char default_gain_table[] = {
#include "ad9361_std_gaintable_default_new.txt"
};
/* Ryan Add */


// 26. 1. 12 Tst to 61.44 MHz Test
#define TEST_6144


#define AD9361 		  "/sys/bus/iio/devices/iio:device0"
#define AD9361_DEBUG  "/sys/kernel/debug/iio/iio:device0"

#define RX_LO_FREQ 	  "out_altvoltage0_RX_LO_frequency"
#define TX_LO_FREQ    "out_altvoltage1_TX_LO_frequency"
#define TX1_ATTEN     "out_voltage0_hardwaregain"
#define TX2_ATTEN     "out_voltage1_hardwaregain"
#define RX1_GAIN      "in_voltage0_hardwaregain"
#define RX2_GAIN      "in_voltage1_hardwaregain"

static int is_vswr_mode = 0;

void set_ad9361_sampling_rate(int rate_hz)
{
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "echo %d > %s/in_voltage_sampling_frequency", rate_hz, AD9361);
    system(cmd);
    printf("[AD9361] Sampling rate set to %d Hz\n", rate_hz);
}


void print_sampling_rate()
{
    char path[128];
    snprintf(path, sizeof(path), "%s/in_voltage_sampling_frequency", AD9361);

    FILE *fp = fopen(path, "r");
    if (!fp) {
        perror("Failed to open sampling_frequency");
        return;
    }

    char buf[64];
    if (fgets(buf, sizeof(buf), fp)) {
        printf("Current sampling rate: %s Hz\n", buf);
    }
    fclose(fp);
}

int ll_register_set(uint32_t addr, int32_t value)
{
	char param[256] = {0};
	char result[32] = {0};

	const char* reg = AD9361_DEBUG"/direct_reg_access";
	int reg_fd = open(reg, O_RDWR);
	sprintf(param, "0x%x 0x%x", addr, value);
	write(reg_fd, (void*)param, strlen(param));
	read(reg_fd, result, sizeof(result));
	close(reg_fd);

	reg_fd = open(reg, O_RDWR);
	read(reg_fd, result, sizeof(result));
	close(reg_fd);

	dev_printf("%s %s Addr 0x%x expected 0x%x result %s", reg, param, addr, value, result);
	return 0;
}

int ll_register_get(uint32_t addr)
{
    char param[256] = {0};
    char result[32] = {0};

    const char* reg = AD9361_DEBUG"/direct_reg_access";
    int reg_fd = open(reg, O_RDWR);
    read(reg_fd, result, sizeof(result));
    close(reg_fd);

    dev_printf("%s %s Addr 0x%x result %s", reg, param, addr, result);
    return 0;
}

void get_ad9361_temp(int* temp)
{

//	char result[128] = {0};

    char buf[128];
	run_shell("cat /sys/bus/iio/devices/iio:device0/in_temp0_input", buf);
	sscanf(buf, "%d", temp);
	*temp /= 1000;

}

int get_ad9361_sampling_frequency(void)
{
    char buf[128];
    int freq = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/in_voltage_sampling_frequency", buf);
    sscanf(buf, "%d", &freq);
    return freq;
}

int get_ad9361_rx1_gain(void)
{
    char buf[128];
    int gain = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/in_voltage0_hardwaregain", buf);
    sscanf(buf, "%d", &gain);
    return gain;
}

int get_ad9361_rx2_gain(void)
{
    char buf[128];
    int gain = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/in_voltage1_hardwaregain", buf);
    sscanf(buf, "%d", &gain);
    return gain;
}

int get_ad9361_tx1_atten(void)
{
    char buf[128];
    float atten = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_voltage0_hardwaregain", buf);
    sscanf(buf, "%f", &atten);
    return (int)(atten * 1000); // Return in mdB
}

int get_ad9361_tx2_atten(void)
{
    char buf[128];
    float atten = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_voltage1_hardwaregain", buf);
    sscanf(buf, "%f", &atten);
    return (int)(atten * 1000); // Return in mdB
}

uint64_t get_ad9361_rx_lo_freq(void)
{
    char buf[128];
    uint64_t freq = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_altvoltage0_RX_LO_frequency", buf);
    sscanf(buf, "%llu", (unsigned long long *)&freq);
    return freq;
}

uint64_t get_ad9361_tx_lo_freq(void)
{
    char buf[128];
    uint64_t freq = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_frequency", buf);
    sscanf(buf, "%llu", (unsigned long long *)&freq);
    return freq;
}

int get_ad9361_rx_rf_bandwidth(void)
{
    char buf[128];
    int bw = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,rf-rx-bandwidth-hz", buf);
    sscanf(buf, "%d", &bw);
    return bw;
}

int get_ad9361_tx_rf_bandwidth(void)
{
    char buf[128];
    int bw = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,rf-tx-bandwidth-hz", buf);
    sscanf(buf, "%d", &bw);
    return bw;
}

int get_ad9361_fir_en(void)
{
    char buf[128];
    int en = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en", buf);
    sscanf(buf, "%d", &en);
    return en;
}

int get_ad9361_rx_port_select(char *port, int max_len)
{
    char buf[128];
    run_shell("cat /sys/bus/iio/devices/iio:device0/in_voltage0_rf_port_select", buf);
    snprintf(port, max_len, "%s", buf);
    // Remove trailing newline
    int len = strlen(port);
    if (len > 0 && port[len-1] == '\n') {
        port[len-1] = '\0';
    }
    return 0;
}

int get_ad9361_tx_port_select(char *port, int max_len)
{
    char buf[128];
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_voltage0_rf_port_select", buf);
    snprintf(port, max_len, "%s", buf);
    // Remove trailing newline
    int len = strlen(port);
    if (len > 0 && port[len-1] == '\n') {
        port[len-1] = '\0';
    }
    return 0;
}

int get_ad9361_1rx_1tx_mode_use_rx_num(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,1rx-1tx-mode-use-rx-num", buf);
    sscanf(buf, "%d", &val);
    return val;
}

int get_ad9361_1rx_1tx_mode_use_tx_num(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,1rx-1tx-mode-use-tx-num", buf);
    sscanf(buf, "%d", &val);
    return val;
}

int get_ad9361_2rx_2tx_mode_enable(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,2rx-2tx-mode-enable", buf);
    sscanf(buf, "%d", &val);
    return val;
}

int get_ad9361_rx_rf_port_input_select(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/kernel/debug/iio/iio:device0/adi,rx-rf-port-input-select", buf);
    sscanf(buf, "%d", &val);
    return val;
}

int get_ad9361_tx_lo_powerdown(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_powerdown", buf);
    sscanf(buf, "%d", &val);
    return val;
}

int get_ad9361_out_voltage2_raw(void)
{
    char buf[128];
    int val = 0;
    run_shell("cat /sys/bus/iio/devices/iio:device0/out_voltage2_raw", buf);
    sscanf(buf, "%d", &val);
    return val;
}

static void set_ad9361_rx_freq(uint64_t freq)
{
    char param[128];
    char result[128];

    // RX Freq
//    printf("set_ad9361_rx_freq %llu\n", freq);
    const char* rx_lo_freq =
                    "/sys/bus/iio/devices/iio:device0/out_altvoltage0_RX_LO_frequency";
    int rx_lo_freq_fd = open(rx_lo_freq, O_RDWR);
    if (rx_lo_freq_fd == -1)
        dev_printf("File Open Error\n");
    sprintf(param, "%llu", freq);
    write(rx_lo_freq_fd, (void*) param, strlen(param));
#if 0
    lseek(rx_lo_freq_fd, 0, SEEK_SET);
    read(rx_lo_freq_fd, (void*) result, sizeof(result));
#endif
    close(rx_lo_freq_fd);
}

static void set_ad9361_tx_freq(uint64_t freq)
{
    char param[128];
    char result[128] = { 0 };
    // TX Freq
    freq -= 900 * 1000; // Bug fix

//    printf("set_ad9361_tx_freq %llu\n", freq);
    const char* tx_lo_freq =
                    "/sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_frequency";

    int tx_lo_freq_fd = open(tx_lo_freq, O_RDWR);
    sprintf(param, "%llu", freq);
    write(tx_lo_freq_fd, (void*) param, strlen(param));
#if 0
    lseek(tx_lo_freq_fd, 0, SEEK_SET);
    read(tx_lo_freq_fd, (void*) result, sizeof(result));
#endif
    close(tx_lo_freq_fd);
}

void set_ad9361_freqeuncy(uint64_t freq)
{
	//Ryan Modified @2023.10.12, to control ad9629 on every frequency change
	if(freq == 10000000) {
		if(get_ad9629_mode()==0) {
			printf("10 Mhz is set, Enable AD9629");
			ad9629_enable();
		}
	}else{
		if(get_ad9629_mode()==1) {
			printf("10 Mhz is set, Enable AD9629");
			ad9629_disable();
		}
		// RX Freq
		set_ad9361_rx_freq(freq);
		// TX Freq
		if (is_vswr_mode) {
			set_ad9361_tx_freq(freq);
		}
	}
	return;
}

int set_ad9361_tx_atten(float atten)
{
	char param[128];
	char result[128] = {0};

	// Atten
	const char* tx1_atten = AD9361"/"TX1_ATTEN;
	int tx1_atten_fd = open(tx1_atten, O_RDWR);
	sprintf(param, "%f", atten);
	write(tx1_atten_fd, (void*)param, strlen(param));
#if 0
	lseek(tx1_atten_fd, 0, SEEK_SET);
	read(tx1_atten_fd, (void*)result, sizeof(result));
//	printf("tx1_atten_fd result %s", result);
#endif
	close(tx1_atten_fd);

	const char* tx2_atten = AD9361"/"TX2_ATTEN;
	int tx2_atten_fd = open(tx2_atten, O_RDWR);
	sprintf(param, "%f", atten);
	write(tx2_atten_fd, (void*)param, strlen(param));
#if 0
	lseek(tx2_atten_fd, 0, SEEK_SET);
	read(tx2_atten_fd, (void*)result, sizeof(result));
//	printf("tx2_atten_fd result %s", result);
#endif
	close(tx2_atten_fd);

	return 0;
}

int set_ad9361_rx_gain(int gain1, int gain2)
{
	char param[128];
	char result[128] = {0};

	// Gain RX1
	const char* rx1_gain = AD9361"/"RX1_GAIN;
	int rx1_gain_fd = open(rx1_gain, O_RDWR);
	sprintf(param, "%d", gain1);
	write(rx1_gain_fd, (void*)param, strlen(param));
#if 0
	lseek(rx1_gain_fd, 0, SEEK_SET);
	read(rx1_gain_fd, (void*)result, sizeof(result));
//	printf("rx1_gain_fd result %s", result);
#endif
	close(rx1_gain_fd);
	// Gain RX2
	const char* rx2_gain = AD9361"/"RX2_GAIN;
	int rx2_gain_fd = open(rx2_gain, O_RDWR);
	sprintf(param, "%d", gain2);
	write(rx2_gain_fd, (void*)param, strlen(param));
#if 0
	lseek(rx2_gain_fd, 0, SEEK_SET);
	read(rx2_gain_fd, (void*)result, sizeof(result));
//	printf("rx2_gain_fd result %s", result);
#endif
	close(rx2_gain_fd);

	return 0;
}

int set_ad9361_rx_gain1(int gain1, int gain2)
{
    char param[128];
    char result[128] = {0};

    // Gain RX1
    const char* rx1_gain = AD9361"/"RX1_GAIN;
    int rx1_gain_fd = open(rx1_gain, O_RDWR);
    sprintf(param, "%d", gain1);
    write(rx1_gain_fd, (void*)param, strlen(param));
#if 0
    lseek(rx1_gain_fd, 0, SEEK_SET);
    read(rx1_gain_fd, (void*)result, sizeof(result));
    //printf("rx1_gain_fd result %s", result);
#endif
    close(rx1_gain_fd);

    return 0;
}

int sa_set_ad9361_rx_gain(uint64_t freq)
{
    /*
    if (freq >= 70000000 && freq <= 140000000) {
        set_ad9361_rx_gain1(16, 0);
    } else if (freq >= 140000001 && freq <= 200000000) {
        set_ad9361_rx_gain1(16, 0);
    } else if (freq >= 200000001 && freq <= 300000000) {
        set_ad9361_rx_gain1(14, 0);
    } else if (freq >= 300000001 && freq <= 400000000) {
        set_ad9361_rx_gain1(10, 0);
    } else if (freq >= 400000001 && freq <= 1460000000) {
        set_ad9361_rx_gain1( 8, 0);
    } else if (freq >= 1460000001 && freq <= 1760000000) {
        set_ad9361_rx_gain1(10, 0);
    } else if (freq >= 1760000000 && freq <= 2050000000) {
        set_ad9361_rx_gain1(14, 0);
    } else if (freq >= 2050000001 && freq <= 2800000000) {
        set_ad9361_rx_gain1(14, 0);
    } else if (freq >= 2800000001 && freq <= 3000000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 3000000001 && freq <= 3500000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 3500000001 && freq <= 4000000000) {
        set_ad9361_rx_gain1(22, 0);
    } else if (freq >= 4000000001 && freq <= 4140000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 4140000001 && freq <= 4900000000) {
        set_ad9361_rx_gain1(22, 0);
    } else if (freq >= 4900000001 && freq <= 6000000000) {
        set_ad9361_rx_gain1(24, 0);
    }
    */
    //printf("-----------------> Set AD9361 Gain at Freq : %lld\n", freq);
    if (freq >= 70000000 && freq <= 200000000) {
        //set_ad9361_rx_gain1(10, 0);
#ifdef ENHANCE_IF_GAIN
        set_ad9361_rx_gain1(14, 0);
#else
        set_ad9361_rx_gain1(18, 0);
#endif
    } else if (freq >= 200000001 && freq <= 400000000) {
        set_ad9361_rx_gain1(18, 0);
    } else if (freq >= 400000001 && freq <= 1460000000) {
        //set_ad9361_rx_gain1(8, 0);
        set_ad9361_rx_gain1(18, 0);
    } else if (freq >= 1460000001 && freq <= 1760000000) {
        //set_ad9361_rx_gain1(10, 0);
        set_ad9361_rx_gain1(18, 0);
    } else if (freq >= 1760000001 && freq <= 2050000000) {
        //set_ad9361_rx_gain1(14, 0);
        set_ad9361_rx_gain1(18, 0);
    } else if (freq >= 2050000001 && freq <= 2800000000) {
        //set_ad9361_rx_gain1(14, 0);
        set_ad9361_rx_gain1(18, 0);
    } else if (freq >= 2800000001 && freq <= 3000000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 3000000001 && freq <= 3500000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 3500000001 && freq <= 4000000000) {
        set_ad9361_rx_gain1(22, 0);
    } else if (freq >= 4000000001 && freq <= 4140000000) {
        set_ad9361_rx_gain1(20, 0);
    } else if (freq >= 4140000001 && freq <= 4900000000) {
        set_ad9361_rx_gain1(22, 0);
    } else if (freq >= 4900000001 && freq <= 6000000000) {
        set_ad9361_rx_gain1(24, 0);
    } else {
        printf("set_ad9361_rx_gain1 Not Found\n");
    }

    return 0;
}

int rx_lo_freq_fd;
int tx_lo_freq_fd;
int tx1_atten_fd;
int tx2_atten_fd;
int rx1_gain_fd;
int rx2_gain_fd;

void fd_init()
{
    const char* rx_lo_freq = AD9361"/"RX_LO_FREQ;
    rx_lo_freq_fd = open(rx_lo_freq, O_RDWR);
    if (rx_lo_freq_fd == -1)
        printf("rx_lo_freq_fd File Open Error\n");

    const char* tx_lo_freq = AD9361"/"TX_LO_FREQ;
    tx_lo_freq_fd = open(tx_lo_freq, O_RDWR);
    if (tx_lo_freq_fd == -1)
        printf("tx_lo_freq_fd File Open Error\n");

    const char* tx1_atten = AD9361"/"TX1_ATTEN;
    tx1_atten_fd = open(tx1_atten, O_RDWR);
    if (tx1_atten_fd == -1)
        printf("tx1_atten_fd File Open Error\n");

    const char* tx2_atten = AD9361"/"TX2_ATTEN;
    tx2_atten_fd = open(tx2_atten, O_RDWR);
    if (tx2_atten_fd == -1)
        printf("tx2_atten_fd File Open Error\n");

    const char* rx1_gain = AD9361"/"RX1_GAIN;
    rx1_gain_fd = open(rx1_gain, O_RDWR);
    if (rx1_gain_fd == -1)
        printf("rx1_gain_fd File Open Error\n");

    const char* rx2_gain = AD9361"/"RX2_GAIN;
    rx2_gain_fd = open(rx2_gain, O_RDWR);
    if (rx2_gain_fd == -1)
        printf("rx2_gain_fd File Open Error\n");

}

void set_out_voltage2_raw(int val)
{
    char cmd[128];

    sprintf(cmd, "echo %d > %s/%s", val, AD9361, "out_voltage2_raw");
    system(cmd);
}

void get_out_voltage2_raw()
{
    char cmd[128];
    char result[128];

    sprintf(cmd, "cat %s/%s", AD9361, "out_voltage2_raw");
    run_shell(cmd, result);
    printf("out_voltage2_raw = %s", result);
}



int set_capture_ad9361_params2(uint64_t freq, int atten, int gain1, int gain2)
{
    //printf("freq %lld %d %d %d\n", freq, atten, gain1, gain2);
    // Freq
    set_ad9361_freqeuncy(freq);

    // Atten
    set_ad9361_tx_atten((float)(atten));

    // Gain
    set_ad9361_rx_gain(gain1, gain2);

    return 0;
}

int set_capture_ad9361_params4(uint64_t freq, int atten, int gain1, int gain2)
{
    // Freq
    set_ad9361_rx_freq(freq);

    // Atten
//    set_ad9361_tx_atten(atten);

    // Gain
    set_ad9361_rx_gain(gain1, gain2);

    return 0;
}
int set_capture_ad9361_params3(uint64_t freq, float atten, int gain1, int gain2)
{
    char param[128];
//    char result[128] = {0};

//    printf("freq %lld %d %d %d\n", freq, atten, gain1, gain2);


    // RX Freq
    sprintf(param, "%llu", freq);
    write(rx_lo_freq_fd, (void*) param, strlen(param));
//    close(rx_lo_freq_fd);

    // TX Freq
    freq -= 900*1000; // Bug fix
    sprintf(param, "%llu", freq);
    write(tx_lo_freq_fd, (void*)param, strlen(param));
//    close(tx_lo_freq_fd);

    // Atten1
    sprintf(param, "%f", atten);
    write(tx1_atten_fd, (void*)param, strlen(param));
//    close(tx1_atten_fd);

    // Atten2
    sprintf(param, "%f", atten);
    write(tx2_atten_fd, (void*)param, strlen(param));
//    close(tx2_atten_fd);

    // Gain RX1
    sprintf(param, "%d", gain1);
    write(rx1_gain_fd, (void*)param, strlen(param));
//    close(rx1_gain_fd);

    // Gain RX2
    sprintf(param, "%d", gain2);
    write(rx2_gain_fd, (void*)param, strlen(param));
//    close(rx2_gain_fd);

    return 0;
}

/* Ryan Add, to update gain tables except VSWR (VSWR use its own gain table */
int init_gain_table(void)
{
	char filename[256] = "";
	FILE *fp = NULL;
	sprintf(filename,"/run/media/mmcblk0p1/ad936x/SA/ad9361_std_gaintable_default.txt");
	/*Ryan Modified, to force update */
	//if(access(filename,F_OK)) {
		fp = fopen(filename,"w");
		if(fp) {
			fprintf(fp,"%s",default_gain_table);
			fclose(fp);
		}
	//}
	/* Ryan Modfied */
	return 0;
}
/* Ryan Add */
/* TODO */
static int cur_type = 0;

//    run_shell("/run/media/mmcblk0p1/ad936x/scripts/reg.sh 0x037 | awk -F' ' '{print $5}'", buf);
int init_ad9361_module(int meas_type)
{
    fd_init();

    init_gain_table();

    printf("%s TYPE: %d\n",__FUNCTION__,meas_type);
    if (meas_type == 0) {
//        if(cur_type != 0) {
//            fw_restart(0);
//        }
//        load_fpga_image(1);
        is_vswr_mode = 1;
        PL_CTRL_Write(MODE_SELECT, 0);

        dev_printf("\t\t[AD9361] initializing for VSWR (TESTING)\n");
        system("echo 1 > " AD9361_DEBUG "/adi,2rx-2tx-mode-enable ");
        system("echo 1 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-rx-num");
        system("echo 1 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-tx-num");

        system("echo 1 > " AD9361_DEBUG "/adi,rx-rf-port-input-select");

        system("echo 9000000 > " AD9361_DEBUG "/adi,rf-rx-bandwidth-hz");
        system("echo 9000000 > " AD9361_DEBUG "/adi,rf-tx-bandwidth-hz");


        system("echo 1 > " AD9361_DEBUG "/initialize");
        usleep(100000);
        system("echo 15360000 > " AD9361 "/out_voltage_sampling_frequency");

        PL_CTRL_Write(0x8c, 1);
        usleep(100000);
        PL_CTRL_Write(0x8c, 0);
        usleep(100000);

//        system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
//        system("echo 0 > "AD9361"/out_altvoltage1_TX_LO_powerdown");

        system("echo B_BALANCED > "AD9361"/in_voltage0_rf_port_select");
        system("echo B_BALANCED > "AD9361"/in_voltage1_rf_port_select");
        system("echo B > "AD9361"/out_voltage0_rf_port_select");
        system("echo B > "AD9361"/out_voltage1_rf_port_select");
//
        printf("Applying /run/media/mmcblk0p1/ad936x/VSWR/pact.fir\n");
        system("cat /run/media/mmcblk0p1/ad936x/VSWR/pact.fir > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        system("echo 1 > /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en");


        /*
         * Direct Register Set for AD9361 SPI
         * register=0x26 0x90   Manual GPIO mode
         * register=0x27 0x10   Amp, Switch control
         *
         */
        ll_register_set(0x26, 0x90);
        ll_register_set(0x27, 0x10);
        ll_register_set(0x51, 0x00);

//        PL_CTRL_Write(SA_EN, 0);
//        PL_CTRL_Write(SA_LNA_CTRL, 0);

        printf("Loading gain table ad9361_std_gaintable.txt\n");
        system("cat /run/media/mmcblk0p1/ad936x/VSWR/ad9361_std_gaintable.txt > /sys/bus/iio/devices/iio:device0/gain_table_config");

    } else if(meas_type == 1 || meas_type == 7) { // SA
        is_vswr_mode = 0;
        PL_CTRL_Write(MODE_SELECT, 1);
        dev_printf("\t\t[AD9361] initializing for SA\n");
        system("echo 0 > " AD9361_DEBUG "/adi,2rx-2tx-mode-enable ");
        system("echo 2 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-rx-num");
        system("echo 0 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-tx-num");

        system("echo 0 > " AD9361_DEBUG "/adi,rx-rf-port-input-select");

        //system("echo 18000000 > " AD9361_DEBUG "/adi,rf-rx-bandwidth-hz");
        //system("echo 18000000 > " AD9361_DEBUG "/adi,rf-tx-bandwidth-hz");

        system("echo 1 > " AD9361_DEBUG "/initialize");
        usleep(100000);

#ifdef TEST_6144

#elif
        system("echo 30720000 > " AD9361 "/in_voltage_sampling_frequency");
#endif

        printf("Applying /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        system("echo 1 > /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en");
        system("echo 1599 > "AD9361"/out_voltage2_raw");

        system("echo A_BALANCED > "AD9361"/in_voltage0_rf_port_select");
        system("echo A_BALANCED > "AD9361"/in_voltage1_rf_port_select");

        system("echo 22 > "AD9361"/in_voltage0_hardwaregain");
        system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
        ll_register_set(0x51, 0x1F);

//        system("echo manual_tx_quad > "AD9361"/calib_mode");

        /*
         * Direct Register Set for AD9361 SPI
         * register=0x169 0xCF   Rx Quadrature Calibartion
         * register=0x026 0x90   Manual GPIO mode
         * register=0x027 0x10   Amp, Switch control
         *
         */
//        ll_register_set(0x169, 0xCF);
        ll_register_set(0x26, 0x90);
        ll_register_set(0x27, 0x00); // AMP Off

        set_atten(0);

        PL_CTRL_Write(SA_EN, 1);
        PL_CTRL_Write(SA_LNA_CTRL, 0);
        PL_CTRL_Write(RF_BAND_CTRL, 0xE);

        // sa_capt_mode     0 : sweep , 1 : general
        PL_CTRL_Write(SA_CAPT_MODE, 1);

        //system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
        //system("echo 0 > "AD9361"/out_altvoltage1_TX_LO_powerdown");

        // Test 30.72 to 61.44 MHz
#ifdef TEST_6144
        set_ad9361_sampling_rate(61440000);
#elif
        set_ad9361_sampling_rate(30720000);
#endif
        print_sampling_rate();

        /* Ryan Add, to update gain tables except VSWR (VSWR use its own gain table */
        printf("Loading gain table ad9361_std_gaintable_default.txt\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/ad9361_std_gaintable_default.txt > /sys/bus/iio/devices/iio:device0/gain_table_config");
        /* Ryan Add */
    } else if (meas_type == 2 || meas_type == 5) { // 5GNR or SG for 5GNR

        is_vswr_mode = 0;
        PL_CTRL_Write(MODE_SELECT, 1);
        dev_printf("\t\t[AD9361] initializing for 5G\n");
        system("echo 2 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-rx-num");
        system("echo 0 > " AD9361_DEBUG "/adi,2rx-2tx-mode-enable ");
        system("echo 1 > " AD9361_DEBUG "/initialize");

#ifdef TEST_6144

#elif
        system("echo 30720000 > " AD9361 "/in_voltage_sampling_frequency");
#endif

        printf("Applying /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr\n");
        /* Ryan Fix, correct wrong filter file path */
        //system("cat /run/media/mmcblk0p1/ad936x/5GNR/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");

        /* Ryan Add, to add SG mode */
        if(meas_type == 5) {
            printf("Applying /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr\n");
            system("cat /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        }else{
        	// JBK : Modify Filter Coef =>
        	//system("cat /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        	//system("cat /run/media/mmcblk0p1/ad936x/5GNR/NR_5G_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
            // 20240131 JBK : Change filter coef as SA_FIR_Coef when correlator version is performed
        	system("cat /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        	int pwr_select = 0; // 0 : ADC, 1 : Cal Block
            PL_CTRL_Write(PWMSR_BLOCK_NUM, (40 | (pwr_select << 8)));
            PL_CTRL_Write(PWMSR_SAMPLE_NUM, 15360);

        	PL_CTRL_Write(COUNTER1_PERIOD, 614400);
        	PL_CTRL_Write(ALT_PERIOD, 800000);
        	// JBK : Modify Filter Coef <=
        }
        /* Ryan Fix */
        system("echo 1 > /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en");
        system("echo 1599 > "AD9361"/out_voltage2_raw");

        system("echo A_BALANCED > "AD9361"/in_voltage0_rf_port_select");
        system("echo A_BALANCED > "AD9361"/in_voltage1_rf_port_select");

        system("echo 22 > "AD9361"/in_voltage0_hardwaregain");
        system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
        ll_register_set(0x51, 0x1F);

        /*
         * Direct Register Set for AD9361 SPI
         * register=0x26 0x90   Manual GPIO mode
         * register=0x27 0x10   Amp, Switch control
         *
         */
        ll_register_set(0x26, 0x90);
        ll_register_set(0x27, 0x00); // AMP Off

        PL_CTRL_Write(SA_EN, 1);
        PL_CTRL_Write(SA_LNA_CTRL, 0);
        PL_CTRL_Write(RF_BAND_CTRL, 0xE);

        // sa_capt_mode     0 : sweep , 1 : general
        PL_CTRL_Write(SA_CAPT_MODE, 1);

        /* Ryan Add, to update gain tables except VSWR (VSWR use its own gain table */
        printf("Loading gain table ad9361_std_gaintable_default.txt\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/ad9361_std_gaintable_default.txt > /sys/bus/iio/devices/iio:device0/gain_table_config");
        /* Ryan Add */

#ifdef TEST_6144
        // Test 30.72 to 61.44 MHz
        set_ad9361_sampling_rate(61440000);
#elif

#endif

        print_sampling_rate();

        /* Ryan Add, to add SG mode */
        if(meas_type == 5) {
			printf("\t\t[AD9361] initializing for SG\n");
			// TX LO frequency, Just use default 2450MHz
			system("cat /sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_frequency");
			usleep(1);

			// Disable TX Power Down
			system("echo 0 > /sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_powerdown");
			usleep(1);
			system("cat /sys/bus/iio/devices/iio:device0/out_altvoltage1_TX_LO_powerdown");
			usleep(1);

			// Set TX Attn -20dB
			system("echo -20 > /sys/bus/iio/devices/iio:device0/out_voltage0_hardwaregain");
			usleep(1);
			system("cat /sys/bus/iio/devices/iio:device0/out_voltage0_hardwaregain");
			usleep(1);

			// TX port B selection
			system("echo B > /sys/bus/iio/devices/iio:device0/out_voltage0_rf_port_select");
			usleep(1);
			system("cat /sys/bus/iio/devices/iio:device0/out_voltage0_rf_port_select");
			usleep(1);

			// TX_1B AMP Enable
			system("/run/media/mmcblk0p1/ad936x/scripts/reg.sh 0x27 0x10");
			usleep(1);
			system("/run/media/mmcblk0p1/ad936x/scripts/reg.sh 0x27");
			usleep(1);

        }
        /* Ryan Add */
    } else if (meas_type == 8) { // 61.44MHz Clock Test Mode
        is_vswr_mode = 0;
        PL_CTRL_Write(MODE_SELECT, 1);
        dev_printf("\t\t[AD9361] initializing for 61.44MHz Test Mode\n");

        // 1Rx-1Tx mode configuration
        system("echo 0 > " AD9361_DEBUG "/adi,2rx-2tx-mode-enable ");
        system("echo 2 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-rx-num");
        system("echo 0 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-tx-num");
        system("echo 0 > " AD9361_DEBUG "/adi,rx-rf-port-input-select");

		// Set RF Bandwidth
		// maximum release analog filter, 56 MHz
		//system("echo 56000000 > " AD9361_DEBUG "/adi,rf-rx-bandwidth-hz");
		//system("echo 56000000 > " AD9361_DEBUG "/adi,rf-tx-bandwidth-hz");

        system("echo 1 > " AD9361_DEBUG "/initialize");
        usleep(100000);

        // Set Atten 0, Preamp Off
        set_atten(0);
        PL_CTRL_Write(SA_LNA_CTRL, 0);

        // Apply 61.44MHz FIR filter (SA_50M_Filter.ftr)
        printf("Applying 61.44MHz Filter: /run/media/mmcblk0p1/ad936x/SA/SA_56M_InvFilter1.ftr\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/SA_56M_InvFilter1.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        system("echo 1 > /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en");

        // Set 61.44MHz sampling rate
        //set_ad9361_sampling_rate(61440000);
        print_sampling_rate();

        // RF port configuration
        system("echo A_BALANCED > "AD9361"/in_voltage0_rf_port_select");
        system("echo A_BALANCED > "AD9361"/in_voltage1_rf_port_select");

        // Gain and power settings
        // init gain setting (saturation gain is over 6 at 0 dBm)
        system("echo 22 > "AD9361"/in_voltage0_hardwaregain");
        system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
        system("echo 1599 > "AD9361"/out_voltage2_raw");
        ll_register_set(0x51, 0x1F);

        // GPIO mode settings
        ll_register_set(0x26, 0x90);  // Manual GPIO mode
        ll_register_set(0x27, 0x00);  // AMP Off

        // FPGA control registers
        PL_CTRL_Write(SA_EN, 1);
        PL_CTRL_Write(SA_LNA_CTRL, 0);
        PL_CTRL_Write(RF_BAND_CTRL, 0xE);
        //PL_CTRL_Write(SA_CAPT_MODE, 1);  // general mode

        // Counter period for 61.44MHz (10ms = 614400 samples)
        PL_CTRL_Write(COUNTER1_PERIOD, 614400);
        PL_CTRL_Write(ALT_PERIOD, 800000);

        // Power measurement settings
        //int pwr_select = 0; // 0 : ADC, 1 : Cal Block
        //PL_CTRL_Write(PWMSR_BLOCK_NUM, (40 | (pwr_select << 8)));
        //PL_CTRL_Write(PWMSR_SAMPLE_NUM, 30720);

        // Load gain table
        printf("Loading gain table ad9361_std_gaintable_default.txt\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/ad9361_std_gaintable_default.txt > /sys/bus/iio/devices/iio:device0/gain_table_config");

        printf("[AD9361] 61.44MHz Test Mode initialized successfully\n");

    } else { // LTE
        is_vswr_mode = 0;
        PL_CTRL_Write(MODE_SELECT, 1);
        dev_printf("\t\t[AD9361] initializing for LTE\n");
        system("echo 2 > " AD9361_DEBUG "/adi,1rx-1tx-mode-use-rx-num");
        system("echo 0 > " AD9361_DEBUG "/adi,2rx-2tx-mode-enable ");
        system("echo 1 > " AD9361_DEBUG "/initialize");

#ifdef TEST_6144
        // Test 30.72 to 61.44 MHz
        set_ad9361_sampling_rate(61440000);
#elif
        system("echo 30720000 > " AD9361 "/in_voltage_sampling_frequency");
#endif
        print_sampling_rate();

        printf("Applying /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/SA_FIR_Coef.ftr > /sys/bus/iio/devices/iio:device0/filter_fir_config");
        system("echo 1 > /sys/bus/iio/devices/iio:device0/in_out_voltage_filter_fir_en");
        system("echo 1599 > "AD9361"/out_voltage2_raw");

        system("echo A_BALANCED > "AD9361"/in_voltage0_rf_port_select");
        system("echo A_BALANCED > "AD9361"/in_voltage1_rf_port_select");

        system("echo 22 > "AD9361"/in_voltage0_hardwaregain");
        system("echo 1 > "AD9361"/out_altvoltage1_TX_LO_powerdown");
        ll_register_set(0x51, 0x1F);

        /*
         * Direct Register Set for AD9361 SPI
         * register=0x26 0x90   Manual GPIO mode
         * register=0x27 0x10   Amp, Switch control
         *
         */
        ll_register_set(0x26, 0x90);
        ll_register_set(0x27, 0x00); // AMP Off

        PL_CTRL_Write(SA_EN, 1);
        PL_CTRL_Write(SA_LNA_CTRL, 0);
        PL_CTRL_Write(RF_BAND_CTRL, 0xE);

        // sa_capt_mode     0 : sweep , 1 : general
        PL_CTRL_Write(SA_CAPT_MODE, 1);

        // LTE Correlator Setting (AlgoLTE removed)
        PL_CTRL_Write(COUNTER1_PERIOD, 307200);
        PL_CTRL_Write(ALT_PERIOD, 400000);
        // lte_corr_blk_cntrl() removed - AlgoLTE module removed

        int pwr_select = 0; // 0 : ADC, 1 : Cal Block
        PL_CTRL_Write(PWMSR_BLOCK_NUM, (20 | (pwr_select << 8)));
        PL_CTRL_Write(PWMSR_SAMPLE_NUM, 15360);

        /* Ryan Add, to update gain tables except VSWR (VSWR use its own gain table */
        printf("Loading gain table ad9361_std_gaintable_default.txt\n");
        system("cat /run/media/mmcblk0p1/ad936x/SA/ad9361_std_gaintable_default.txt > /sys/bus/iio/devices/iio:device0/gain_table_config");
        /* Ryan Add */
        //  set_ad9361_tx_atten(0);

        // AMP control
        //
    }

    cur_type = meas_type;

    // Freq CAL
    char freq_cal[32]={0,};
    char freq_cal_cmd[128]={0,};
    char* cmd = "cat /run/media/mmcblk0p1/freq_cal.conf | awk '{printf $1}'";
    run_shell(cmd, freq_cal);
    sprintf(freq_cal_cmd, "echo %s > "AD9361"/out_voltage2_raw", freq_cal);
    system(freq_cal_cmd); // cal freq
    printf("freq_cal is set to %s\n", freq_cal);
    return 0;
}


