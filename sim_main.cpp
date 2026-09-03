//
// Adapted from Antmicro's axi_ram sample for PL_DDR_BRAM co-simulation.


// Adapted from Antmicro's axi_ram sample for PL_DDR_BRAM co-simulation.

#include <verilated.h>
#include "Vtop_axi_wrapper.h"
#include <bitset>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#if VM_TRACE
#include <verilated_vcd_c.h>
#endif
#include "src/buses/axi.h"
#include "src/renode.h"

RenodeAgent *pl_ddr_bram = new RenodeAgent;
Vtop_axi_wrapper *top = new Vtop_axi_wrapper;
VerilatedVcdC *tfp = nullptr;
vluint64_t main_time = 0;

void eval() {
#if VM_TRACE
        main_time++;
        if (tfp) {
            tfp->dump(main_time);
            // tfp->flush() left out per cycle to avoid Renode timeout errors
        }
#endif
    top->eval();
}

void initAgent(RenodeAgent *agent)
{
    Axi* bus = new Axi(32, 32);

    //=================================================
    // Init bus signals
    //=================================================
    bus->aclk = &top->clk;
    bus->aresetn = &top->rst;

    bus->awid = &top->s_axi_awid;
    bus->awaddr = (uint32_t *) &top->s_axi_awaddr;
    bus->awlen = &top->s_axi_awlen;
    bus->awsize = &top->s_axi_awsize;
    bus->awburst = &top->s_axi_awburst;
    bus->awlock = &top->s_axi_awlock;
    bus->awcache = &top->s_axi_awcache;
    bus->awprot = &top->s_axi_awprot;
    bus->awvalid = &top->s_axi_awvalid;
    bus->awready = &top->s_axi_awready;

    bus->wdata = &top->s_axi_wdata;
    bus->wstrb = &top->s_axi_wstrb;
    bus->wlast = &top->s_axi_wlast;
    bus->wvalid = &top->s_axi_wvalid;
    bus->wready = &top->s_axi_wready;

    bus->bid = &top->s_axi_bid;
    bus->bresp = &top->s_axi_bresp;
    bus->bvalid = &top->s_axi_bvalid;
    bus->bready = &top->s_axi_bready;

    bus->arid = &top->s_axi_arid;
    bus->araddr = (uint32_t *) &top->s_axi_araddr;
    bus->arlen = &top->s_axi_arlen;
    bus->arsize = &top->s_axi_arsize;
    bus->arburst = &top->s_axi_arburst;
    bus->arlock = &top->s_axi_arlock;
    bus->arcache = &top->s_axi_arcache;
    bus->arprot = &top->s_axi_arprot;
    bus->arvalid = &top->s_axi_arvalid;
    bus->arready = &top->s_axi_arready;

    bus->rid = &top->s_axi_rid;
    bus->rdata = &top->s_axi_rdata;
    bus->rresp = &top->s_axi_rresp;
    bus->rlast = &top->s_axi_rlast;
    bus->rvalid = &top->s_axi_rvalid;
    bus->rready = &top->s_axi_rready;

    bus->evaluateModel = &eval;

    //=================================================
    // Init peripheral
    //=================================================
    agent->addBus(bus);
}

void closeTrace() {
#if VM_TRACE
    if (tfp) {
        tfp->flush();
        tfp->close();
        delete tfp;
        tfp = nullptr;
    }
#endif
}

RenodeAgent *Init() {
#if VM_TRACE
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    // top->trace(tfp, 99);
    top->trace(tfp, 1);
    
    // Use an absolute path so Renode can't hide the file anywhere else:
    tfp->open("/home/abisankar_aity/vivado_linux/vivado_project/project_zynq_WOS_2024_2/Zynq_DDR_BRAM/verilator_build/build/simx.vcd");
    
    atexit(closeTrace);
#endif

    pl_ddr_bram->connectNative();
    initAgent(pl_ddr_bram);
    return pl_ddr_bram;
}

int main(int argc, char **argv, char **env) {
    if(argc < 3) {
        printf("Usage: %s {receiverPort} {senderPort} [{address}]\n", argv[0]);
        exit(-1);
    }
    const char *address = argc < 4 ? "127.0.0.1" : argv[3];

    Verilated::commandArgs(argc, argv);
#if VM_TRACE
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    
    // Updated to absolute path so Renode creates simx.vcd right inside your build folder
    tfp->open("/home/abisankar_aity/vivado_linux/vivado_project/project_zynq_WOS_2024_2/Zynq_DDR_BRAM/verilator_build/build/simx.vcd");
#endif

    pl_ddr_bram->connect(atoi(argv[1]), atoi(argv[2]), address);
    initAgent(pl_ddr_bram);
    pl_ddr_bram->simulate();

#if VM_TRACE
    if (tfp) {
        tfp->close();
        delete tfp;
        tfp = nullptr;
    }
#endif

    top->final();
    exit(0);
}