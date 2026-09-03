cmake_minimum_required(VERSION 3.8)

# Name of the project
project(top_axi_wrapper)

# Verilog files to be Verilated (top-level wrapper first, then the instantiated module)
set(VTOP top_axi_wrapper.v PL_DDR_BRAM.v)

# C/C++ source files to be compiled
set(CSOURCES sim_main.cpp)

# Additional compiling, linking or verilating arguments
set(COMP_LIB_ARGS -fPIC)

# Ensure --trace is explicitly included here so Verilator builds waveform tracing support into libVtop.so
set(VERI_EXEC_ARGS -Wno-WIDTH -Wno-CASEINCOMPLETE --trace)
set(VERI_LIB_ARGS -Wno-WIDTH -Wno-CASEINCOMPLETE --trace)

# CMake file doing the hard job (absolute path - our build folder is outside the repo)
include(/root/renode-verilator-integration/cmake/configure-and-verilate.cmake)