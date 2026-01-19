# f32c XRAM SDRAM c2 Makefile
# Open-source toolchain: GHDL + Yosys + nextpnr-ecp5
#
# Uses f32c_cache_ghdl.vhd which fixes the unused M_i_bram signal issue
#

PROJ=f32c_xram
FPGA_SIZE?=12
CONSTRAINTS=ulx3s_nextpnr.lpf
SYNTH_SCRIPT=synth.ys

# Path to RTL root (relative to this Makefile location)
RTL_ROOT=$(shell cd ../../../.. && pwd)

# Docker image for synthesis
SYNTH_IMAGE=hdlc/ghdl:yosys
DOCKER_SYNTH=docker run --rm -v "$(RTL_ROOT):/src" -w /src/proj/lattice/ulx3s/xram_sdram_12f_v2.0_c2_noscripts_trellis $(SYNTH_IMAGE)

# Default target: synthesis with Docker
all: $(PROJ).bit

# Synthesis with Docker container
$(PROJ).json: $(SYNTH_SCRIPT) Makefile $(wildcard *.vhd)
	$(DOCKER_SYNTH) yosys -m ghdl $(SYNTH_SCRIPT)

# Place and route with nextpnr-ecp5
$(PROJ).config: $(PROJ).json $(CONSTRAINTS)
	nextpnr-ecp5 --$(FPGA_SIZE)k --speed 6 --package CABGA381 \
		--json $(PROJ).json \
		--lpf $(CONSTRAINTS) \
		--lpf-allow-unconstrained \
		--timing-allow-fail \
		--textcfg $(PROJ).config

# Bitstream generation
$(PROJ).bit: $(PROJ).config
	ecppack --compress $(PROJ).config $(PROJ).bit

# Program ULX3S board
prog: $(PROJ).bit
	fujprog $<

# Clean build artifacts
clean:
	rm -f $(PROJ).bit $(PROJ).config $(PROJ).json
	rm -f *.json *.config *.bit
	rm -f *~

.PHONY: all prog clean
