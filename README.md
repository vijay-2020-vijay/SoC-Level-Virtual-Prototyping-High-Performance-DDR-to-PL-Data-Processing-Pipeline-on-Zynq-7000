<div align="center">

# 🌟🌟 SoC-Level Virtual Prototyping
## High-Performance DDR ↔ PL Data Processing Pipeline on Zynq-7000

### *A Full-Stack Hardware/Software Co-Design Framework for AXI CDMA, Dual-Port BRAM & PS-PL Handshaking — Verified Without a Physical Board*

<br/>

[![Platform](https://img.shields.io/badge/Platform-Xilinx%20Zynq--7000-blue?style=for-the-badge&logo=xilinx)](#)
[![HDL](https://img.shields.io/badge/HDL-Verilog%20RTL-orange?style=for-the-badge)](#)
[![Simulation](https://img.shields.io/badge/Co--Sim-Verilator%20%2B%20Renode-red?style=for-the-badge)](#)
[![Waveform](https://img.shields.io/badge/Debug-GTKWave-9cf?style=for-the-badge)](#)
[![Status](https://img.shields.io/badge/Status-Verified%20%26%20Passing-success?style=for-the-badge)](#)
[![License](https://img.shields.io/badge/License-MIT-lightgrey?style=for-the-badge)](#)

<br/>

**[📁 Download Full Project Package (Google Drive)](https://drive.google.com/file/d/1ZAVyFyPXAbd8olpM0ASr3neKbUt1IoKs/view?usp=sharing)** &nbsp;•&nbsp; **[👤 Author: Rabisankar Maity](https://www.linkedin.com/in/rabisankar-maity-98572b1b7/)** &nbsp;•&nbsp; **[✉️ Contact](mailto:rabisankarmaity8250@gmail.com)**

</div>

---

## ⬜⬜ Overview

This repository contains an **end-to-end SoC-level virtual prototyping framework** built around the Xilinx Zynq-7000 architecture. It demonstrates a complete **DDR ↔ Programmable-Logic (PL) data processing pipeline**, where 64-bit datasets are moved by an **AXI Central DMA (CDMA)** engine, buffered in **asymmetric dual-port Block RAM**, transformed by a **custom hand-written Verilog finite-state machine**, and synchronized with the **ARM Cortex-A9 Processing System** through a purpose-built **GPIO-based handshaking protocol**.

The entire system — ARM core, AXI fabric, and custom RTL — was verified **without ever touching a physical FPGA board**, using a **Verilator-compiled hardware model co-simulated inside Renode**, executing the exact same bare-metal ELF that would run on real silicon. Every transaction was then cross-checked cycle-by-cycle in **GTKWave**.

> **In short:** this project proves a complete PS↔PL data pipeline — architecture, RTL, embedded C, and full-stack verification — end to end, entirely in software.

---

## ⭐⭐ Why This Project Matters

Most student FPGA projects stop at "it compiles" or "LED blinks on board." This one goes several levels deeper:

| Challenge Tackled | How It Was Solved |
|---|---|
| **No physical Zynq board available** | Built a Verilator-based cycle-accurate RTL model and attached it to Renode as a co-simulated peripheral — the *exact* bare-metal ELF built in Vitis runs unmodified |
| **AXI protocol overhead on a tight compute loop** | Split memory access into two planes: AXI/CDMA uses Port A of each BRAM (64-bit, bulk), the custom FSM uses Port B directly (32-bit, zero AXI overhead) |
| **PS and PL must stay perfectly synchronized with no OS, no interrupts** | Designed a level-sensitive, 5-state GPIO handshake protocol — not edge-triggered, immune to a single missed poll |
| **DMA writes are not cache-coherent with the ARM core** | Explicit `Xil_DCacheFlushRange` / `Xil_DCacheInvalidateRange` calls bracket every CDMA transfer in the embedded C driver |
| **Co-simulation can silently hang** | GPIO polling loop has a bounded retry counter with a timeout warning, so a stuck handshake fails loud instead of hanging forever |
| **Debugging RTL with no board and no JTAG/ILA** | Full GTKWave waveform capture of every AXI, BRAM, and handshake signal — VCD converted to compact FST for fast loading |

---

## 🏗️ System Architecture & Data Flow

The system coordinates memory transfers and hardware acceleration across the Zynq **Processing System** (PS — ARM Cortex-A9) and **Programmable Logic** (PL):

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/zynq-soc-architecture-dataflow-diagram.png" width="850"/>
<br/><sub><b>Fig 1.</b> End-to-end SoC data-flow — DDR → CDMA → BRAM0 → PL FSM → BRAM1 → CDMA → DDR</sub>
</p>

```
DDR (0x10000000) ──(64-bit AXI CDMA)──> BRAM0 Port A ──(Dual-Port)──> BRAM0 Port B
                                                                            │
                                                                   PL_DDR_BRAM FSM
                                                                   (32-bit read, +0x5, write)
                                                                            │
                                                              BRAM1 Port B <──(Dual-Port)
                                                                   │
                                      DDR (0x10010000) <──(64-bit AXI CDMA)── BRAM1 Port A
```

---

## ◉◉ Pipeline Execution Stages

| Stage | Description |
|---|---|
| **1. DDR → BRAM0** | An embedded `.hex` dataset (630 × 64-bit entries) is parsed into PS DDR at `0x10000000`, then streamed over 64-bit AXI CDMA into BRAM0 (Port A) — 256 entries / 2048 bytes transferred. |
| **2. PL Processing Engine** | A custom Verilog FSM reads 32-bit words from BRAM0 (Port B), applies a hardware arithmetic transform (`data + 0x5`), and pipelines the modified results into BRAM1 (Port B) — 512 × 32-bit accesses. |
| **3. BRAM1 → DDR** | Transformed data sitting in BRAM1 (Port A) is transferred back to a destination DDR region (`0x10010000`) via CDMA, then read back and printed by the PS for verification. |
| **Handshaking** | AXI GPIO Channels 1 & 2 (5 control bits out, 4 status bits in) drive a strict, level-sensitive synchronization protocol between the ARM CPU and the PL FSM at every stage boundary. |

---

## ◉◉ Detailed Block-Level Architecture (Vivado IP Integrator)

The Vivado block design implements **four distinct planes**, each using the interconnect best suited to its purpose — this separation deliberately keeps AXI protocol overhead off the hot compute path.

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-zynq7000-pl-ddr-bram-subsystem-design.png" width="850"/>
<br/><sub><b>Fig 2.</b> Full Vivado IP Integrator block design — PS, CDMA, interconnects, dual BRAM controllers, custom FSM</sub>
</p>

### ◉◉ Control Plane — AXI4-Lite *(PS configures hardware)*

```
PS (M_AXI_GP0) → AXI SmartConnect → axi_cdma_0  (S_AXI_LITE)  — configure DMA transfers
                                   → axi_gpio_0   (S_AXI)       — drive/read handshake bits
```

The embedded C application writes CDMA transfer descriptors (source/destination address, length, start bit) and toggles or polls GPIO bits. **No bulk data passes through this path.**

### ◉◉ Data Plane — AXI4-Full *(bulk memory-to-memory transfers)*

```
axi_cdma_0 (M_AXI) → AXI Interconnect → M00_AXI → axi_bram_ctrl_0 → blk_mem_gen_0 (BRAM0, Port A)
                                       → M01_AXI → axi_bram_ctrl_1 → blk_mem_gen_1 (BRAM1, Port A)
                                       → M02_AXI → PS (S_AXI_HP0)  → DDR
```

AXI CDMA is the **only** bus master performing bulk transfers, moving data DDR↔BRAM0 and BRAM1↔DDR through the interconnect to three separate slave targets.

### ◉◉ Direct RTL Access Plane — raw dual-port BRAM *(no AXI overhead)*

```
blk_mem_gen_0 (Port B) ⟷ PL_DDR_BRAM_v1_0   — reads BRAM0 directly (bram0_addrb, bram0_doutb, bram0_web...)
blk_mem_gen_1 (Port B) ⟷ PL_DDR_BRAM_v1_0   — writes BRAM1 directly (bram1_addrb, bram1_dinb, bram1_web...)
```

Since each Block Memory Generator instance is **true dual-port**, Port A is dedicated to the AXI/CDMA side while Port B connects straight into the custom FSM. The processing core never has to speak AXI — it accesses memory like a plain register file, eliminating protocol overhead on the compute path.

### ◉◉ Handshake Plane — GPIO-based synchronization

```
axi_gpio_0 GPIO  (5-bit out) → xlslice_0..4 → individual 1-bit control lines into PL_DDR_BRAM_v1_0:
                                                 DDR_BRAM0_W, BRAM0_BRAM1_W, BRAM1_DDR_W,
                                                 BRAM1_DDR_W_com, restar_process_w

PL_DDR_BRAM_v1_0 status outputs → ilconcat_0 (4-bit concat) → axi_gpio_0 GPIO2 (4-bit in) → PS polls status
```

- **Slice blocks** (`xlslice_0`–`xlslice_4`) split the single 5-bit GPIO output bus into individual 1-bit trigger signals the FSM can consume separately.
- **Inline Concat** (`ilconcat_0`) merges four separate 1-bit status flags from the FSM into a single 4-bit bus so the PS can read all status in one GPIO2 register access.

### ◉◉ Clock & Reset Distribution

```
PS FCLK_CLK0      → single clock domain driving every PL block (CDMA, interconnect, GPIO, BRAM controllers, custom FSM)
PS FCLK_RESET0_N  → proc_sys_reset_0 → synchronized resets (peripheral_reset, interconnect_aresetn, bus_struct_reset...)
                                        fanned out to every IP's reset pin
```

### 📋 IP Summary Table

| IP Block | Role |
|---|---|
| `processing_system7_0` | Zynq PS — ARM Cortex-A9, runs the embedded application, owns DDR controller |
| `proc_sys_reset_0` | Generates synchronized resets for every clock domain in the PL |
| `axi_cdma_0` | AXI Central DMA — performs DDR↔BRAM0 and BRAM1↔DDR transfers |
| `smartconnect_0` | Routes PS's AXI4-Lite master to CDMA and GPIO control interfaces |
| `axi_interconnect_0` | Routes CDMA's AXI4-Full master to BRAM controllers and the PS HP port |
| `axi_gpio_0` | Dual-channel GPIO — outputs FSM triggers, inputs FSM status flags |
| `axi_bram_ctrl_0` / `axi_bram_ctrl_1` | AXI-to-BRAM bridges, exposing Port A of each memory to the AXI fabric |
| `blk_mem_gen_0` / `blk_mem_gen_1` | True dual-port block RAM — BRAM0 (input buffer) and BRAM1 (result buffer) |
| `xlslice_0`–`xlslice_4` | Split the 5-bit GPIO output bus into individual 1-bit control signals |
| `ilconcat_0` | Merge four 1-bit FSM status flags into a single 4-bit GPIO input bus |
| `PL_DDR_BRAM_v1_0` | Custom RTL — the processing FSM; reads BRAM0 / writes BRAM1 via direct Port B access |

---

## 🌟🌟 The PS–PL Handshake Protocol (Core Engineering Contribution)

The custom `PL_DDR_BRAM` module implements a **5-state, level-sensitive finite-state machine** — deliberately avoiding interrupts and AXI-Stream in favor of a transparent, fully observable GPIO protocol that is easy to verify in waveform.

| State | Trigger (PS → PL) | PL Action | Acknowledgement (PL → PS) |
|:---:|---|---|---|
| **s0** | `DDR_BRAM0_W` asserted, then **de-asserted** once CDMA finishes | Waits specifically for the **falling edge** of the trigger — synchronized to when the PS clears the GPIO bit after CDMA completes | `DDR_BRAM0_trans_com_out = 1` |
| **s1** | `BRAM0_BRAM1_w = 1` | Arms both BRAM ports (`bram0_enb`, `bram1_enb`, `bram1_web = 4'hF`), resets address counters | `trans_out = 1` |
| **s2** | *(internal pipeline loop)* | 512-cycle pipelined read/transform/write: `bram1_dinb <= bram0_doutb + 0x5`, addresses incremented by 4 bytes each cycle, with a 1-cycle latency offset to stay aligned with BRAM0's registered read data | `BRAM0_BRAM1_trans_com_out = 1` on completion |
| **s3** | `BRAM1_DDR_W = 1` | Gate state — actual transfer work is performed by CDMA in the C driver | `trans_out = 1` |
| **s4** | `BRAM1_DDR_W_com = 1` | Final acknowledgement; `restar_process_w` returns the FSM to `s0` for the next cycle | `comple_transaction_out = 1`, `transaction_finish_out = 1` |

> **Design note:** the s0 handshake intentionally triggers on the trigger signal going **low**, not high — matching the embedded C driver, which asserts the GPIO bit, waits for the CDMA hardware to finish, and *then* clears it. The FSM is watching for that specific clear, not the initial pulse — a level-based protocol immune to single-cycle glitches.

---

## 🌟🌟 Source Code Highlights

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-pl-ddr-bram-verilog-source-code-editor.png" width="850"/>
<br/><sub><b>Fig 3.</b> PL_DDR_BRAM.v — the custom handshaking FSM in the Vivado RTL editor</sub>
</p>

**Verilog FSM (`PL_DDR_BRAM.v`)**
- Single always block, `posedge clk / negedge rst_n`, fully synchronous
- Dual-port BRAM interfaces exposed as raw Port B signals (address, din, dout, enable, write-enable) — no AXI wrapper on this path
- Pipelined 32-bit transform loop with explicit latency compensation (`bram1_addrb` incremented only once `data_count > 1`, to stay aligned with BRAM0's one-cycle-delayed read data)

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vitis-ide-embedded-c-helloworld-source-code.png" width="850"/>
<br/><sub><b>Fig 4.</b> Vitis IDE — bare-metal C application driving CDMA and GPIO</sub>
</p>

**Bare-Metal C Application**
- `.incbin` assembler directive embeds the `.hex` dataset directly into the ELF's `.rodata` section at compile time — no filesystem needed in a bare-metal environment
- `strtoull`-based hex parser loads 630 × 64-bit entries into DDR at runtime
- Explicit cache management around every DMA transfer: `Xil_DCacheFlushRange()` before CDMA reads DDR, `Xil_DCacheInvalidateRange()` before the PS reads CDMA-written DDR
- `poll_gpio_until_set()` — a bounded-retry GPIO poll (2,000,000 iterations) with a timeout warning, preventing an indefinite lockup if a co-simulation handshake stalls

---

## 📁 Repository Structure & File Details

### Complete Archives

- **Google Drive (Full Project Package):** [📁 Download Here](https://drive.google.com/file/d/1ZAVyFyPXAbd8olpM0ASr3neKbUt1IoKs/view?usp=sharing)
- `for_Vivado.zip` — Complete Vivado block design (`.bd`), IP configuration parameters, and top-level synthesis source files.
- `for_vitis/` — Platform board support packages (BSP), system project settings, and C application source code.

### Repository Files

| File Name | Description |
|---|---|
| [`CMakeLists.txt`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/CMakeLists.txt) | CMake build configuration script for compiling RTL sources with Verilator into a Renode shared library plugin. |
| [`DDR_BRAM_DDR_2_2.elf`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_DDR_2_2.elf) | Bare-metal executable compiled via Vitis containing application logic and embedded `.hex` data parser. |
| [`DDR_BRAM_HEX.hex`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_HEX.hex) | Raw input dataset containing 630 hex-formatted 64-bit entries embedded into the PS program memory section. |
| [`PL_DDR_BRAM.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/PL_DDR_BRAM.v) | Core RTL processing module implementing asymmetric BRAM control, state machine logic, and PS-PL handshaking. |
| [`Zynq_DDR_BRAM_wrapper.xsa`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/Zynq_DDR_BRAM_wrapper.xsa) | Exported Vivado hardware platform specification containing memory map address definitions and IP metadata. |
| [`sim_main.cpp`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/sim_main.cpp) | Verilator C++ simulation testbench wrapper enabling socket bridge communication between RTL and Renode. |
| [`top_axi_wrapper.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/top_axi_wrapper.v) | Top-level Verilog wrapper interfacing the PL processing core to AXI-Lite and AXI-Full interconnects. |
| [`Zynq_DDR_BRAM_images2/`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/tree/main/Zynq_DDR_BRAM_images2) | Experimental execution logs, terminal verification traces, Vivado screenshots, and GTKWave waveform captures. |

---

## 🌟🌟 Prerequisites & Build Tools

| Tool | Purpose |
|---|---|
| **Xilinx Vivado / Vitis** (v2024.2 or compatible) | EDA tools for hardware design and embedded software |
| **Renode Engine Framework** | Virtual platform / co-simulation environment |
| **Verilator** (v4.200+) & **CMake** | HDL verifier / RTL-to-C++ simulation build system |
| **GTKWave** & `vcd2fst` utility | Waveform analysis |

---

## 🌟🌟 Execution & Co-Simulation Setup

### 1. Compile the Verilator Shared Model

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
```

### 2. Launch Renode Co-Simulation

```bash
renode project_zynq_DDR_BRAM.resc
```

#### 📜 `project_zynq_DDR_BRAM.resc` — Script Walkthrough

The Renode script boots a virtual Zynq-7000 platform, attaches the Verilator-compiled PL model as a co-simulated peripheral, loads the bare-metal application, and starts execution.

| # | Command | Purpose |
|---|---|---|
| 1 | `mach create` | Creates a fresh virtual machine instance in Renode. |
| 2 | `machine LoadPlatformDescription @platforms/boards/zedboard.repl` | Loads the predefined ZedBoard platform (Zynq-7000 PS: ARM Cortex-A9, UART, timers, interrupt controller, default memory map). |
| 3 | `sysbus Unregister memory` | Removes the default memory region from the base platform description, avoiding address conflicts with the custom-sized region. |
| 4 | `machine LoadPlatformDescriptionFromString 'progRam: Memory.MappedMemory @ sysbus 0x0 { size: 0x10000000 }'` | Defines a 256 MB DDR memory region at address `0x0`, used for application code, stack, and the embedded `.hex` dataset. |
| 5 | `machine LoadPlatformDescriptionFromString 'pl_ddr_bram: CoSimulated.CoSimulatedPeripheral @ sysbus <0x10000000, +0xB2000900> { frequency: 100000000; limitBuffer: 10000; timeout: 240000 }'` | Maps the custom PL processing core (built via Verilator) into the address space at `0x10000000`. Sets PL clock frequency (100 MHz), event buffer limit, and simulation timeout. |
| 6 | `sysbus WriteDoubleWord 0xE0000000 0x14` | Writes to the Zynq SLCR register to configure a clock/reset control bit required before the PS can drive the PL clock domain. |
| 7 | `showAnalyzer sysbus.uart0` | Opens a live terminal window for UART0 output — where the embedded application's debug logs appear. |
| 8 | `sysbus.pl_ddr_bram SimulationFilePathLinux @<path>/libVtop.so` | Links the compiled Verilator shared library (RTL model) to the co-simulated peripheral. |
| 9 | `sysbus LoadELF @<path>/DDR_BRAM_DDR_2_2.elf` | Loads the Vitis-compiled bare-metal ELF into the virtual DDR memory defined in step 4. |
| 10 | `start` | Begins execution — the PS boots, runs the ELF, and drives the PL peripheral via the AXI interconnect. |

<details>
<summary><b>📄 Click to expand the full <code>.resc</code> script</b></summary>

```tcl
# ------------------------------------------------------------------
# 1. Machine Creation
# ------------------------------------------------------------------
mach create

# ------------------------------------------------------------------
# 2. Load Base Platform Description
# ------------------------------------------------------------------
machine LoadPlatformDescription @platforms/boards/zedboard.repl

# ------------------------------------------------------------------
# 3. Remove Default Program Memory
# ------------------------------------------------------------------
sysbus Unregister memory

# ------------------------------------------------------------------
# 4. Redefine Program Memory (DDR)
# ------------------------------------------------------------------
machine LoadPlatformDescriptionFromString 'progRam: Memory.MappedMemory @ sysbus 0x0 { size: 0x10000000 }'

# ------------------------------------------------------------------
# 5. Attach the Co-Simulated PL Peripheral
# ------------------------------------------------------------------
machine LoadPlatformDescriptionFromString 'pl_ddr_bram: CoSimulated.CoSimulatedPeripheral @ sysbus <0x10000000, +0xB2000900> { frequency: 100000000; limitBuffer: 10000; timeout: 240000 }'

# ------------------------------------------------------------------
# 6. Configure Slave Control Register (SLCR)
# ------------------------------------------------------------------
sysbus WriteDoubleWord 0xE0000000 0x14

# ------------------------------------------------------------------
# 7. Enable UART Console Output
# ------------------------------------------------------------------
showAnalyzer sysbus.uart0

# ------------------------------------------------------------------
# 8. Link the Verilator Shared Library
# ------------------------------------------------------------------
# NOTE: Update this path to match your own build output location.
sysbus.pl_ddr_bram SimulationFilePathLinux @/path/to/verilator_build/build/libVtop.so

# ------------------------------------------------------------------
# 9. Load the Bare-Metal Application
# ------------------------------------------------------------------
# NOTE: Update this path to match your own Vitis build output.
sysbus LoadELF @/path/to/DDR_BRAM_DDR_2_2/Debug/DDR_BRAM_DDR_2_2.elf

# ------------------------------------------------------------------
# 10. Start Simulation
# ------------------------------------------------------------------
start
```

</details>

> 🌟🌟 **Note:** Replace the two `@/path/to/...` entries in steps 8 and 9 with the absolute paths on your own machine before running the script.

### 3. Compress & Analyze GTKWave Waveforms

To prevent UI performance bottlenecks on large simulation files, convert raw VCD traces into compressed FST format prior to viewing:

```bash
# Convert raw text VCD (e.g., 4.2GB) to lean binary FST (~1.4MB)
vcd2fst simx.vcd simx.fst

# Launch GTKWave using FST mode
gtkwave simx.fst &
```

---

## 🖼️ Visual Design Walkthrough

A complete visual trail of the project — from PS configuration, through RTL schematics and synthesis results, to full-chip implementation.

### Zynq PS Configuration & Address Map

<table>
<tr>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-ip-integrator-zynq-ps-configuration-gui.png"/>
<br/><sub><b>Zynq-7000 PS Configuration GUI</b> — HP/GP AXI ports, clocking, and peripheral enablement</sub>
</td>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-ip-integrator-address-editor-map.png"/>
<br/><sub><b>Vivado Address Editor</b> — memory map for DDR, BRAM0/BRAM1, CDMA, and GPIO base addresses</sub>
</td>
</tr>
</table>

### RTL Schematics & FPGA Floorplan

<table>
<tr>
<td width="33%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-top-level-schematic-io-buffers.png"/>
<br/><sub><b>Top-Level Schematic</b> — I/O buffers and port-level connectivity</sub>
</td>
<td width="33%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-expanded-rtl-schematic-net-interconnects.png"/>
<br/><sub><b>Expanded RTL Schematic</b> — net-level interconnects inside the synthesized design</sub>
</td>
<td width="33%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-device-view-fpga-floorplan-routing.png"/>
<br/><sub><b>Device View</b> — FPGA floorplan and physical routing after implementation</sub>
</td>
</tr>
</table>

### Implementation Reports

<table>
<tr>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-project-summary-dashboard-timing-utilization.png"/>
<br/><sub><b>Project Summary Dashboard</b> — timing closure and resource utilization at a glance</sub>
</td>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-implementation-utilization-report-hierarchy.png"/>
<br/><sub><b>Utilization Report</b> — hierarchical resource breakdown by IP block</sub>
</td>
</tr>
</table>

---

## 🧮 Experimental Results & Verification

This section showcases simulation logs, co-simulation UART output, and GTKWave waveform traces demonstrating hardware state transitions and DDR memory transactions — the actual proof that the pipeline works end to end.

### Vivado Behavioral Simulation

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/vivado-simulation-waveform-bram-states.png" width="850"/>
<br/><sub><b>Fig 5.</b> Vivado behavioral simulation — FSM state transitions and BRAM port activity, verified in isolation before co-simulation</sub>
</p>

### Renode Co-Simulation — UART Console Output

<table>
<tr>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/renode-successful-cosimulation-uart-output.png"/>
<br/><sub><b> ◉ Successful Co-Simulation</b> — full pipeline log: hex load → Stage 1 → Stage 2 → Stage 3 → verified results in DDR</sub>
</td>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/renode-cosimulation-timeout-error-uart-log.png"/>
<br/><sub><b> ◉ Timeout/Debug Log</b> — an early-stage handshake timeout captured during bring-up, kept here to show real debugging history, not just the final success case</sub>
</td>
</tr>
</table>

> Including a captured *failure* log alongside the final passing log is intentional — it shows the actual debug cycle: the bounded-retry timeout mechanism in `poll_gpio_until_set()` was added specifically in response to hangs like this one, and this screenshot is the evidence trail for that design decision.

### GTKWave Waveform Verification

<p align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/gtkwave-full-timeline-simulation-waveform.png" width="850"/>
<br/><sub><b>Fig 6.</b> GTKWave — full simulation timeline, compressed to FST for fast rendering of a multi-gigabyte VCD trace</sub>
</p>

<table>
<tr>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/gtkwave-simulation-complete-timeline-view.png"/>
<br/><sub><b>Complete Timeline View</b> — end-to-end signal activity across all three pipeline stages</sub>
</td>
<td width="50%" align="center">
<img src="https://raw.githubusercontent.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/main/Zynq_DDR_BRAM_images2/gtkwave-detailed-simulation-waveform-axi-bram.png"/>
<br/><sub><b>AXI / BRAM Detail View</b> — cycle-accurate zoom on AXI handshakes and BRAM address/data activity</sub>
</td>
</tr>
</table>

### ◉◉ Key Verification Highlights

- **CDMA Transfer Validation** — Confirmed 64-bit transfers from DDR (`0x10000000`) into BRAM0, and from BRAM1 back into DDR (`0x10010000`).
- **PL State Machine Transitions** — Observed continuous, correct execution through the state loop (`s0 → s1 → s2 → s3 → s4`), each transition driven by the expected AXI GPIO pulse.
- **Data Integrity Check** — Verified transformed data values (`input + 0x5`) stored correctly at the DDR destination address, matching the expected output for all 256 processed entries.
- **Protocol Robustness** — Captured and resolved a real co-simulation timeout during development, hardening the GPIO polling logic with bounded retries.
- **Multi-Level Verification** — Design validated at three independent levels: Vivado behavioral simulation → Verilator/Renode full-system co-simulation (running the actual compiled ELF) → GTKWave cycle-accurate waveform inspection.

---

## 🗺️ Repository File Index (Quick Links)

| Category | Files |
|---|---|
| **RTL Source** | [`PL_DDR_BRAM.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/PL_DDR_BRAM.v) · [`top_axi_wrapper.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/top_axi_wrapper.v) |
| **Co-Sim Infra** | [`sim_main.cpp`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/sim_main.cpp) · [`CMakeLists.txt`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/CMakeLists.txt) |
| **Embedded SW** | [`DDR_BRAM_DDR_2_2.elf`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_DDR_2_2.elf) |
| **Data** | [`DDR_BRAM_HEX.hex`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_HEX.hex) |
| **Hardware Platform** | [`Zynq_DDR_BRAM_wrapper.xsa`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/Zynq_DDR_BRAM_wrapper.xsa) |
| **Images / Logs** | [`Zynq_DDR_BRAM_images2/`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/tree/main/Zynq_DDR_BRAM_images2) |

---

## ◉◉ Tech Stack Summary

`Verilog RTL` · `Xilinx Vivado` · `Xilinx Vitis` · `AXI4 / AXI4-Lite` · `AXI CDMA` · `Dual-Port BRAM` · `AXI GPIO` · `Verilator` · `Renode` · `C (Bare-Metal)` · `GTKWave` · `CMake`

---

## ◉◉ Contributing

Issues, suggestions, and pull requests are welcome. If you spot a bug in the handshake protocol, find a cleaner way to pipeline the BRAM transform, or want to extend this to more BRAM stages or a different data transform — feel free to open an issue.

---

## 📄 License

This project is released under the **MIT License** — free to use, modify, and build upon with attribution.

---

## 👤 About the Author

<div align="center">

### Rabisankar Maity

**RTL Design Engineer** | M.Tech VLSI & Nanoelectronics @ IIT Guwahati '26 *(GATE AIR 318)*
**Verilog • SystemVerilog • FPGA • SoC PL+PS Integration**
*Creator of a Full VGG-16 Hardware Accelerator & a RISC-V Core | UVM Verification & IP Integration*

◉◉ [rabisankarmaity8250@gmail.com](mailto:rabisankarmaity8250@gmail.com)
◉◉ [LinkedIn — rabisankar-maity](https://www.linkedin.com/in/rabisankar-maity-98572b1b7/)
◉◉ [GitHub — vijay-2020-vijay](https://github.com/vijay-2020-vijay)

<br/>

**If this project helped you understand Zynq PS-PL co-design, AXI CDMA, or RTL/software co-simulation — a ⭐ on the repo is always appreciated!**

</div>
