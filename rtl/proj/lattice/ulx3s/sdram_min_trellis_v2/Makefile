# f32c sdram_min Makefile
# Synthesis: Docker with GHDL+Yosys (hdlc/ghdl:yosys)
# P&R: local nextpnr-ecp5 (from oss-cad-suite)

PROJ=sdram_min
FPGA_SIZE?=12
CONSTRAINTS=ulx3s_nextpnr.lpf

# Path to RTL root (relative to this Makefile location)
RTL_ROOT=$(shell cd ../../../.. && pwd)

# Docker image for synthesis (public image with stable GHDL+Yosys)
SYNTH_IMAGE=hdlc/ghdl:yosys
DOCKER_SYNTH=docker run --rm -v "$(RTL_ROOT):/src" -w /src/proj/lattice/ulx3s/sdram_min_trellis_v2 $(SYNTH_IMAGE)

all: $(PROJ).bit

# Synthesis with GHDL+Yosys via Docker
$(PROJ).json: synth_docker.ys Makefile $(wildcard *.vhd)
	$(DOCKER_SYNTH) yosys -m ghdl synth_docker.ys

# Place and route with nextpnr-ecp5 (local installation)
$(PROJ).config: $(PROJ).json $(CONSTRAINTS)
	nextpnr-ecp5 --$(FPGA_SIZE)k --speed 6 --package CABGA381 \
		--json $(PROJ).json \
		--lpf $(CONSTRAINTS) \
		--lpf-allow-unconstrained \
		--timing-allow-fail \
		--textcfg $(PROJ).config

# Bitstream generation (local installation)
$(PROJ).bit: $(PROJ).config
	ecppack --compress $(PROJ).config $(PROJ).bit

# Program ULX3S board
prog: $(PROJ).bit
	fujprog $<

clean:
	rm -f $(PROJ).bit $(PROJ).config $(PROJ).json *~

.PHONY: all prog clean
