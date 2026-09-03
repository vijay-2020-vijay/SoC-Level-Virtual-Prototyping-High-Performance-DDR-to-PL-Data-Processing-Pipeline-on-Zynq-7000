SoC-Level Virtual Prototyping: High-Performance DDR-to-PL Data Processing Pipeline on Zynq-7000An end-to-end SoC-level virtual prototyping framework for the Xilinx Zynq-7000 architecture. This project demonstrates a high-throughput DDR-to-PL data processing pipeline using AXI CDMA, dual-port BRAM controllers, and custom hardware-software handshaking—fully verified inside a software co-simulation environment powered by Renode and Verilator.📌 System Architecture & Data FlowThe system coordinates memory transfers and hardware acceleration across the Zynq Processing System (PS ARM Cortex-A9) and Programmable Logic (PL):Plaintext  +-----------------------------------------------------------------------------------+
  |                                 PROCESSING SYSTEM (PS)                            |
  |   [ Embedded C Application ] ---> [ AXI GPIO Control ] ---> [ DDR Memory Base ]   |
  +------------------------------------------+----------------------------------------+
                                             |
                  +--------------------------+--------------------------+
                  |                                                     |
                  v                                                     v
  +-------------------------------+                     +-------------------------------+
  |        AXI CDMA ENGINE        |                     |      CUSTOM HANDSHAKE (GPIO)  |
  +---------------+---------------+                     +---------------+---------------+
                  |                                                     |
  (64-bit Port A) v                                                     v (State Signals)
  +-------------------------------+                     +-------------------------------+
  |  BRAM0 (DDR Buffer Storage)   |                     |     PL PROCESSING ENGINE      |
  +---------------+---------------+                     |   (32-bit Async Port B)       |
                  | (32-bit Read)                       |  Custom Math Transformation   |
                  +------------------------------------>+                               |
                                                        |  (State Machine s0 -> s4)     |
  (64-bit Port A) ^                                     +---------------+---------------+
  +---------------+---------------+                                     |
  |  BRAM1 (Result Storage Space) |<------------------------------------+ (32-bit Write)
  +---------------+---------------+
                  |
  (64-bit Read)   v
  +-------------------------------+
  |     DESTINATION DDR SPACE     | ---> [ Verification & Cache Invalidation ]
  +-------------------------------+
Pipeline Execution StagesStage 1 (DDR -> BRAM0): Embedded .hex dataset loaded into PS DDR (0x10000000) is streamed over 64-bit AXI CDMA into BRAM0 (Port A).Stage 2 (PL Processing Engine): Custom Verilog FSM reads 32-bit entries from BRAM0 (Port B), applies hardware arithmetic operations (+0x5), and pipelines modified results into BRAM1 (Port B).Stage 3 (BRAM1 -> DDR): Transformed data in BRAM1 (Port A) is transferred back to destination DDR space (0x10010000) via CDMA for validation.Handshaking: GPIO Channels 1 & 2 handle step-by-step synchronization between the ARM CPU and PL FSM states.📁 Repository Structure & File DetailsComplete ArchivesGoogle Drive Link (Full Projects): [Insert Google Drive Link Here]for_Vivado.zip: Contains complete Vivado block design (.bd), IP configuration parameters, and top-level synthesis source files.for_vitis/: Contains platform board support packages (BSP), system project settings, and C application source code.Repository FilesFile NameDescriptionCMakeLists.txtCMake build configuration script for compiling RTL sources with Verilator into a Renode shared library plugin.DDR_BRAM_DDR_2_2.elfBare-metal executable compiled via Vitis containing application logic and embedded .hex data parser.DDR_BRAM_HEX.hexRaw input dataset containing 630 hex-formatted 64-bit entries embedded into the PS program memory section.PL_DDR_BRAM.vCore RTL processing module implementing asymmetric BRAM control, state machine logic, and PS-PL handshaking.Zynq_DDR_BRAM_wrapper.xsaExported Vivado hardware platform specification containing memory map address definitions and IP metadata.sim_main.cppVerilator C++ simulation testbench wrapper enabling socket bridge communication between RTL and Renode.top_axi_wrapper.vTop-level Verilog wrapper interfacing the PL processing core to AXI-Lite and AXI-Full interconnects.Zynq_DDR_BRAM_images/Folder containing experimental execution logs, terminal verification traces, and GTKWave waveform dumps.🛠️ Prerequisites & Build ToolsEDA Tools: Xilinx Vivado / Vitis (v2024.2 or compatible)Virtual Platform: Renode Engine FrameworkHDL Verifier: Verilator (v4.200+) & CMakeWaveform Analysis: GTKWave & vcd2fst utility🚀 Execution & Co-Simulation Setup1. Compile Verilator Shared ModelBashmkdir build && cd build
cmake ..
make -j$(nproc)
2. Launch Renode Co-SimulationBashrenode project_zynq_DDR_BRAM.resc
3. Compress & Analyze GTKWave WaveformsTo prevent UI performance bottlenecks on large simulation files, convert raw VCD traces into compressed FST format prior to viewing:Bash# Convert raw text VCD (e.g., 4.2GB) to lean binary FST (~1.4MB)
vcd2fst simx.vcd simx.fst

# Launch GTKWave using FST mode
gtkwave simx.fst &
📊 Experimental Results & VerificationThis section showcases simulation logs and GTKWave trace outputs demonstrating hardware state transitions and DDR memory transactions.Renode Console Execution LogGTKWave Signal VerificationKey Verification Highlights:CDMA Transfer Validation: Confirmed 64-bit transfers from DDR (0x10000000) into BRAM0.PL State Machine Transitions: Observed continuous execution through state loop (s0 to s4) driven by AXI GPIO pulses.Data Integrity Check: Verified transformed data values (0x...DEADBEEF / incremented hex strings) stored in DDR target address (0x10010000).
