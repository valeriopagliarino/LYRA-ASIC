# Cocotb + Icarus Verilog Makefile for the LYRA audio testbench.
#
# IMPORTANT: this repo only contains the RTL files that were shared for
# this testbench (project.sv, lyra_topl.sv, spi_regfile.sv). Add the
# remaining LYRA submodules below before running `make`:

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES = 1

VERILOG_SOURCES += ../src/project.v
VERILOG_SOURCES += ../src/lyra_topl.sv
VERILOG_SOURCES += ../src/spi_regfile.sv
VERILOG_SOURCES += ../src/i2s_decoder.sv
VERILOG_SOURCES += ../src/i2s_encoder.sv
VERILOG_SOURCES += ../src/adat8enc.sv
VERILOG_SOURCES += ../src/dsp.sv
VERILOG_SOURCES += ../src/vu.sv
VERILOG_SOURCES += ../src/clock_div.sv

TOPLEVEL = tt_um_lyra
MODULE   = test_lyra

COCOTB_HDL_TIMEUNIT      = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

export PYTHONPATH := $(PWD)/test:$(PYTHONPATH)
export LYRA_INPUT_WAV ?= $(PWD)/stimuli/input.wav

include $(shell cocotb-config --makefiles)/Makefile.sim