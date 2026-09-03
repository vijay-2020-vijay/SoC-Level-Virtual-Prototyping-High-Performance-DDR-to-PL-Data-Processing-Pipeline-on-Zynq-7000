# SoC-Level Virtual Prototyping: High-Performance DDR-to-PL Data Processing Pipeline on Zynq-7000

A complete hardware-software co-design pipeline demonstrating true SoC-level integration — where the ARM Cortex-A9 Processing System (PS) and custom Programmable Logic (PL) communicate through AXI CDMA, AXI GPIO, and dual-port Block RAMs, verified end-to-end through both Vivado/Vitis hardware co-simulation and an independent Verilator-based software co-simulation environment.

This isn't just RTL design. It's a working proof of the exact integration discipline — cache-coherent DMA transfers, handshake-driven PS-PL protocols, and cross-domain verification — that real embedded SoC platforms are built on.

---

## 📦 Full Project Download

All Vivado and Vitis project files, the exported hardware platform, RTL, embedded C application, and simulation environment are packaged together.

**[⬇️ Download Full Project (Google Drive)](PASTE_YOUR_GOOGLE_DRIVE_LINK_HERE)**

---

## 🔧 Data Flow Architecture

```
DDR (0x10000000) ──[AXI CDMA, 64-bit]──▶ BRAM0 (Port A)
                                              │
                                    [Port B, 32-bit read]
                                              ▼
                                    PL Processing Engine
                                     (custom arithmetic + FSM)
                                              │
                                    [Port B, 32-bit write]
                                              ▼
BRAM1 (Port A) ──[AXI CDMA, 64-bit]──▶ DDR (0x10010000)
```

- **Stage 1:** 630 hex entries loaded into DDR from the ARM Cortex-A9 side; 256 entries streamed into BRAM0 via AXI CDMA (64-bit).
- **Stage 2:** PL engine reads 32-bit words from BRAM0 Port B, applies a custom arithmetic transformation, writes to BRAM1 Port B — governed by a 5-state FSM (`s0`→`s4`) with a fully handshake-driven PS-PL protocol over AXI GPIO.
- **Stage 3:** Processed data read back via CDMA into DDR, verified, and acknowledged through a completion handshake back to the PS.

---

## ⚙️ Engineering Highlights

- **Cycle-accurate BRAM latency compensation** — the write address to BRAM1 is deliberately delayed by one cycle relative to the BRAM0 read address, correctly compensating for BRAM's synchronous read latency across a 512-cycle processing loop.
- **Explicit cache coherency management** — `Xil_DCacheFlushRange` / `Xil_DCacheInvalidateRange` calls surround every CDMA transfer, ensuring the ARM core and DMA engine never operate on stale data.
- **Timeout-protected handshaking** — GPIO status polling includes a bounded retry limit to prevent indefinite lockups during co-simulation, rather than relying on a fragile happy-path handshake.
- **Level-based PS-PL handshake protocol** — deliberately designed (not edge-triggered) for robustness across the full transaction lifecycle, including safe restart via a dedicated `restart_process` signal.
- **Dual verification paths** — validated both through Vivado/Vitis on-target co-simulation *and* an independent Verilator + CMake C++ simulation environment, the same dual-path verification discipline used in industry regression flows.

---

## 🧩 Tools & Environment

- **Vivado 2024.2** — Block design, RTL integration, hardware platform export
- **Vitis** — Embedded C application development and PS-side control software
- **Linux (Ubuntu / WSL2)** — Full development and build environment
- **Verilator + CMake** — Independent C++-driven RTL co-simulation, outside Vivado's built-in simulator
- **GTKWave** — Waveform-level verification, with VCD-to-FST conversion for efficient large-scale waveform handling

---

## 📂 File & Folder Structure

### `for_Vivado/` *(inside the downloaded ZIP)*
Contains the complete Vivado project — the block design (PS-PL interconnect, AXI CDMA, AXI GPIO, dual-port BRAMs) and the custom Verilog RTL implementing the PL processing engine.

### `for_Vitis/` *(inside the downloaded ZIP)*
Contains the embedded C application — including both the **platform project** (BSP, hardware handoff from the exported `.xsa`) and the **application project** (the control software driving the DDR→BRAM0→BRAM1→DDR pipeline via AXI GPIO and AXI CDMA).

### Repository Files

| File | Description |
|---|---|
| [`PL_DDR_BRAM.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/PL_DDR_BRAM.v) | Core PL RTL — the 5-state FSM managing DDR↔BRAM0↔BRAM1 data flow and PS handshaking |
| [`top_axi_wrapper.v`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/top_axi_wrapper.v) | Top-level wrapper used for the Verilator co-simulation build |
| [`sim_main.cpp`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/sim_main.cpp) | Verilator C++ testbench driver for standalone RTL simulation |
| [`CMakeLists.txt`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/CMakeLists.txt) | Build configuration for the Verilator simulation environment |
| [`DDR_BRAM_HEX.hex`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_HEX.hex) | 630-entry hex data file loaded into DDR at runtime |
| [`DDR_BRAM_DDR_2_2.elf`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/DDR_BRAM_DDR_2_2.elf) | Compiled Vitis application binary, ready to run on the Cortex-A9 |
| [`Zynq_DDR_BRAM_wrapper.xsa`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/Zynq_DDR_BRAM_wrapper.xsa) | Exported hardware platform from Vivado, for Vitis platform project creation |
| [`Zynq_DDR_BRAM_images/`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/tree/main/Zynq_DDR_BRAM_images) | Block design, waveform, and architecture screenshots |
| [`README.md`](https://github.com/vijay-2020-vijay/SoC-Level-Virtual-Prototyping-High-Performance-DDR-to-PL-Data-Processing-Pipeline-on-Zynq-7000/blob/main/README.md) | Project documentation |

---

## 📸 Architecture & Verification Visuals

*(Paste your images into `Zynq_DDR_BRAM_images/` and update filenames below to match.)*

![Block Design — PS-PL Interconnect](Zynq_DDR_BRAM_images/block_design.png)
![Data Flow Architecture Diagram](Zynq_DDR_BRAM_images/dataflow_architecture.png)
![GTKWave Simulation Waveform](Zynq_DDR_BRAM_images/gtkwave_verification.png)

---

## 🧪 Expert Details

<!-- Add your in-depth technical notes, edge cases, and design rationale here. -->

---

## 🎯 Why This Project Matters

This project demonstrates the exact integration pattern real embedded SoC platforms depend on: AXI-based memory-mapped I/O, DMA-driven data movement, cache-coherent PS-PL communication, and rigorous cross-tool hardware/software co-verification — built and validated end-to-end on a Linux-based toolchain, the same discipline used in production SoC bring-up before physical silicon is ever touched.

---

## 👤 Author

**Rabisankar Maity**
VLSI M.Tech Graduate, IIT Guwahati — AIR 318 in GATE EC
Feel free to connect, raise issues, or fork this project for your own experiments.
