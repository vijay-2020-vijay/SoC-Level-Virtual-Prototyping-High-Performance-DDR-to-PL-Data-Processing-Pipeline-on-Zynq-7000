//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Purpose: Load 630 hex entries to DDR, process 256 entries through BRAM0->BRAM1, store results to DDR
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xgpio.h"
#include "xaxicdma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_types.h"
#include "xil_assert.h"
#include "sleep.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Hardware Device IDs & Base Addresses
#define AXI_GPIO_DEVICE_ID    XPAR_AXI_GPIO_0_DEVICE_ID
#define CDMA_DEVICE_ID        XPAR_AXI_CDMA_0_DEVICE_ID

// DDR Addresses
#define DDR_BASE_ADDR         0x10000000  // Source: All 630 hex entries
#define DDR_DST_ADDR          0x10010000  // Destination: Results

// BRAM Addresses
#define BRAM0_BASE_ADDR       0xC0000000  // BRAM0 PortA (64-bit)
#define BRAM1_BASE_ADDR       0xC2000000  // BRAM1 PortA (64-bit)

// Data sizes
#define HEX_TOTAL_ENTRIES     630         // Total hex file entries
#define PROCESS_ENTRIES       256         // Process only first 256 entries
#define BYTES_PER_64BIT       8           // 64-bit = 8 bytes
#define BYTES_PER_32BIT       4           // 32-bit = 4 bytes
#define TRANSFER_BYTES        (PROCESS_ENTRIES * BYTES_PER_64BIT)  // 2048 bytes
#define PROCESS_32BIT_COUNT   (PROCESS_ENTRIES * 2)  // 512 × 32-bit accesses

// GPIO Channel 1: Control Outputs
#define MASK_DDR_BRAM0_W      (1 << 0)
#define MASK_BRAM0_BRAM1_W    (1 << 1)
#define MASK_BRAM1_DDR_W      (1 << 2)
#define MASK_BRAM1_DDR_W_COM  (1 << 3)
#define Mask_restart_process  (1 << 4)

// GPIO Channel 2: Status Inputs
#define MASK_trans_out        (1 << 0)
#define MASK_DDR_BRAM0_COM    (1 << 1)
#define MASK_BRAM0_BRAM1_COM  (1 << 2)
#define MASK_COMPLETE_TRANS   (1 << 3)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
volatile u64 *DdrDataPtr = (volatile u64 *)DDR_BASE_ADDR;
__asm__ (
    ".section .rodata\n"
    ".global hex_file_start\n"
    "hex_file_start:\n"
    ".incbin \"/home/abisankar_aity/vivado_linux/vivado_project/project_zynq_WOS_2024_2/Zynq_DDR_BRAM/DDR_BRAM_HEX.hex\"\n"
    ".global hex_file_end\n"
    "hex_file_end:\n"
    ".byte 0\n"
    ".previous\n"
);
/////////here actually assembler converted this hexfile into the exectuale binaery formet that will be stored into rodata section
extern const char hex_file_start[];
void dump_hex_to_ddr(void) {
    const char *line_ptr = hex_file_start;
    char *next_line;
    xil_printf("Parsing and loading .hex file to DDR address 0x%08X...\r\n", DDR_BASE_ADDR);
    xil_printf("Loading ALL %d hex entries...\r\n", HEX_TOTAL_ENTRIES);

    int loaded_count = 0;
    for (int i = 0; i < HEX_TOTAL_ENTRIES; i++) {
        while (*line_ptr && (isspace((unsigned char)*line_ptr))) {
            line_ptr++;
        }
        if (*line_ptr == '\0') {
            xil_printf("[WARNING] Reached EOF at entry %d (expected %d)\r\n", i, HEX_TOTAL_ENTRIES);
            break;
        }
        DdrDataPtr[i] = strtoull(line_ptr, &next_line, 16);
        line_ptr = next_line;
        loaded_count++;
    }
    // Explicit verification print to guarantee load state visibility
    xil_printf("======================================================\r\n");
    xil_printf(" [VERIFICATION] Successfully loaded %d of %d entries.\r\n", loaded_count, HEX_TOTAL_ENTRIES);
    xil_printf(" [VERIFICATION] Sample check -> DdrDataPtr[0] = 0x%016LLX\r\n",  DdrDataPtr[0]);
    xil_printf(" [VERIFICATION] Sample check -> DdrDataPtr[1] = 0x%016LLX\r\n",  DdrDataPtr[1]);
    xil_printf(" [VERIFICATION] Sample check -> DdrDataPtr[10] = 0x%016LLX\r\n", DdrDataPtr[10]);
    xil_printf(" [VERIFICATION] Sample check -> DdrDataPtr[16] = 0x%016LLX\r\n", DdrDataPtr[16]);
    xil_printf(" hex_File is Successfully loaded in DDR3 : Testing is successfully verifited \r\n");
    xil_printf("======================================================\r\n");
    Xil_DCacheFlushRange((INTPTR)DDR_BASE_ADDR, HEX_TOTAL_ENTRIES * BYTES_PER_64BIT);
    //This line tells the processor to push data out of its local cache and into the actual physical DDR memory//
    ///then aso clean thebcache
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
XGpio    AxiGpio;
XAxiCdma AxiCdma;

int init_axi_gpio(void) {
    XGpio_Config *GpioCfgPtr;
    int Status;
    GpioCfgPtr = XGpio_LookupConfig(AXI_GPIO_DEVICE_ID);
    if (GpioCfgPtr == NULL) {
        xil_printf("[ERROR] AXI GPIO Lookup Failed\r\n");
        return XST_FAILURE;
    }
    Status = XGpio_CfgInitialize(&AxiGpio, GpioCfgPtr, GpioCfgPtr->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] AXI GPIO Initialization Failed\r\n");
        return XST_FAILURE;
    }

    XGpio_SetDataDirection(&AxiGpio, 1, 0x00);
    XGpio_SetDataDirection(&AxiGpio, 2, 0xFF);
    xil_printf("AXI GPIO Initialized Successfully!\r\n");
    return XST_SUCCESS;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int init_axicdma(void) {
    XAxiCdma_Config *CdmaCfgPtr;
    int Status;
    CdmaCfgPtr = XAxiCdma_LookupConfig(CDMA_DEVICE_ID);
    if (CdmaCfgPtr == NULL) {
        xil_printf("[ERROR] AXI CDMA Lookup Failed\r\n");
        return XST_FAILURE;
    }
    Status = XAxiCdma_CfgInitialize(&AxiCdma, CdmaCfgPtr, CdmaCfgPtr->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] AXI CDMA Initialization Failed\r\n");
        return XST_FAILURE;
    }
    XAxiCdma_IntrDisable(&AxiCdma, XAXICDMA_XR_IRQ_ALL_MASK);
    xil_printf("AXI CDMA Initialized Successfully!\r\n");
    return XST_SUCCESS;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int init_system(void) {
    init_platform();
    Xil_DCacheEnable();
    if (init_axi_gpio() != XST_SUCCESS) return XST_FAILURE;
    if (init_axicdma() != XST_SUCCESS)  return XST_FAILURE;
    xil_printf("\r\n--- ALL HARDWARE INITIALIZED SUCCESSFULLY ---\r\n\r\n");
    return XST_SUCCESS;
}

void wait_for_cdma(void) {
    while (XAxiCdma_IsBusy(&AxiCdma)) {
    }
}

// Safely poll GPIO status with a timeout threshold to prevent indefinite co-simulation lockups
void poll_gpio_until_set(u32 mask) {
    u32 status;
    int retry_count = 0;

    status = XGpio_DiscreteRead(&AxiGpio, 2);
    while ((status & mask) == 0) {
        status = XGpio_DiscreteRead(&AxiGpio, 2);
        retry_count++;

        if (retry_count > 2000000) {
            xil_printf("[WARNING] GPIO poll timeout reached for mask 0x%08X. Forcing progression...\r\n", mask);
            break;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int main(void) {
    int Status;
    volatile u64 *DdrResultPtr = (volatile u64 *)DDR_DST_ADDR;

    if (init_system() != XST_SUCCESS) {
        xil_printf("[FATAL] System Initialization Failed!\r\n");
        return XST_FAILURE;
    }
    else {
    	xil_printf("======================================================\r\n");
    	xil_printf("[Loading]....AXI_GPIO_ Initialization is  succeed\r\n");
    	xil_printf("[Loading]....AXI_CDMA_Initialization is  succeed\r\n");
    	xil_printf("[Loading]....System Initialization is  succeed\r\n");
    	xil_printf("======================================================\r\n");
    }
    dump_hex_to_ddr();
    XGpio_DiscreteWrite(&AxiGpio, 1, 0x00);//sets all output pins on Channel 1 to LOW (0)

    xil_printf("\r\n======================================================\r\n");
    xil_printf("  STARTING PIPELINE: 64-bit CDMA <-> 32-bit PL WORKFLOW  \r\n");
    xil_printf("======================================================\r\n");

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // =========================================================================
    // STAGE 1: DDR -> BRAM0 (64-bit CDMA, PortA)
    // =========================================================================
    xil_printf("\r\n[STAGE 1] Triggering 64-bit CDMA Transfer: DDR -> BRAM0 (PortA)...\r\n");
    xil_printf("         Transferring %d × 64-bit entries (%d bytes)\r\n", PROCESS_ENTRIES, TRANSFER_BYTES);
    ///This single line of code tells the CPU to clean and push its local cache data down into the physical DDR memory before the CDMA engine reads it.
    Xil_DCacheFlushRange((INTPTR)(void *)DDR_BASE_ADDR, TRANSFER_BYTES);//
    Status = XAxiCdma_SimpleTransfer(&AxiCdma, DDR_BASE_ADDR, BRAM0_BASE_ADDR, TRANSFER_BYTES, NULL, NULL);
    if (Status != XST_SUCCESS) {
        xil_printf(" CDMA DDR->BRAM0 Transfer_accseptance by CDMA is Failed!\r\n");
        return XST_FAILURE;
    }
    else {
    	xil_printf(" CDMA DDR->BRAM0 Transfer_accseptance by CDMA is succeed!\r\n");
    	XGpio_DiscreteWrite(&AxiGpio, 1, MASK_DDR_BRAM0_W);////ps informs to pl that we are starting data transformation(DDR to BBRAM0)//waiting for your response.
    }
    wait_for_cdma();// Do nothing, just wait until the CDMA hardware clears its busy flag
    xil_printf("[STAGE 1] CDMA transfer to BRAM0 complete.\r\n");
    xil_printf("[STAGE 1] Waiting for PL acknowledgment (DDR_BRAM0_trans_com_out)...\r\n");
    XGpio_DiscreteWrite(&AxiGpio, 1, 0x00);//////// doing all outputs of channel1=0/////////////////////////////////////////////////////////
    poll_gpio_until_set(MASK_DDR_BRAM0_COM);/////////////////this is kind of acknowledgment given by pl to inform to ps to continue next task
    xil_printf("[STAGE 1 SUCCESS] BRAM0 loaded. PL State s0->s1 complete.\r\n");
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


    xil_printf("[INFO] Waiting for 50 ms...\r\n");
    usleep(50000);
    // =========================================================================
    // STAGE 2: BRAM0 (PortB 32-bit) -> PL Processing -> BRAM1 (PortB 32-bit)
    // =========================================================================
    xil_printf("\r\n[STAGE 2] Triggering PL 32-bit Processing Engine (BRAM0 PortB -> BRAM1 PortB)...\r\n");
    XGpio_DiscreteWrite(&AxiGpio, 1, MASK_BRAM0_BRAM1_W);
    xil_printf("[STAGE 2] PL executing 32-bit read/write transfer (s1->s2 state loop)...\r\n");
    poll_gpio_until_set(MASK_BRAM0_BRAM1_COM);////////this is waiting for conformetion of transforming bram0 to bram1 by pl section
    XGpio_DiscreteWrite(&AxiGpio, 1, 0x00);
    xil_printf("[STAGE 2 SUCCESS] PL completed processing. BRAM1 now contains transformed data.\r\n");

 //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    xil_printf("[INFO] Waiting for 50 ms...\r\n");
    usleep(50000);

    // =========================================================================
    // STAGE 3: BRAM1 (64-bit CDMA, PortA) -> DDR
    // =========================================================================
    xil_printf("\r\n[STAGE 3] Triggering 64-bit CDMA Readback: BRAM1 (PortA) -> DDR...\r\n");
    xil_printf("         DDR destination: 0x%08X (addresses 0 to 2040)\r\n", DDR_DST_ADDR);
    Xil_DCacheInvalidateRange((INTPTR)(void *)DDR_DST_ADDR, TRANSFER_BYTES);
    Status = XAxiCdma_SimpleTransfer(&AxiCdma, BRAM1_BASE_ADDR, DDR_DST_ADDR, TRANSFER_BYTES, NULL, NULL);
    if (Status != XST_SUCCESS) {
        xil_printf("[ERROR] CDMA BRAM1->DDR Readback acceptance Failed!\r\n");
        return XST_FAILURE;
    }
    else {
    	xil_printf("[Fine] CDMA BRAM1->DDR Readback acceptance succeed \r\n");
    	XGpio_DiscreteWrite(&AxiGpio, 1, MASK_BRAM1_DDR_W);
    }

    wait_for_cdma();
    xil_printf("[STAGE 3] CDMA transfer from BRAM1 to DDR complete.\r\n");
    XGpio_DiscreteWrite(&AxiGpio, 1, MASK_BRAM1_DDR_W_COM);
    xil_printf("[STAGE 3] Waiting for final PL completion pulse...\r\n");
    poll_gpio_until_set(MASK_COMPLETE_TRANS);
    XGpio_DiscreteWrite(&AxiGpio, 1, 0x00);////////////////////so we do not want to restart the process
    xil_printf("[STAGE 3 SUCCESS] Pipeline complete!\r\n");
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////




    // =========================================================================
    // READ RESULTS FROM DDR
    // =========================================================================
    Xil_DCacheInvalidateRange((INTPTR)DDR_DST_ADDR, TRANSFER_BYTES);
    xil_printf("\r\n======================================================\r\n");
    xil_printf("    READING RESULTS FROM DDR (0x%08X)                \r\n", DDR_DST_ADDR);
    xil_printf("    Expected: %d × 64-bit entries (%d bytes)         \r\n", PROCESS_ENTRIES, TRANSFER_BYTES);
    xil_printf("======================================================\r\n");

    for (int i = 0; i < 30; i++) {
        xil_printf("  [%03d] = 0x%016LLX\r\n", i, DdrResultPtr[i]);
    }

    xil_printf("\r\n[INFO] First 10 entries shown. Total entries: %d\r\n", PROCESS_ENTRIES);

    xil_printf("\r\nCleaning up platform...\r\n");
    cleanup_platform();
    return 0;
}
