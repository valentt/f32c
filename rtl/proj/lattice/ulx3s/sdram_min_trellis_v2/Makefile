# f32c sdram_min Makefile
# Two synthesis options:
#   make        - uses local GHDL+Yosys (Linux/macOS with oss-cad-suite)
#   make docker - uses Docker container (Windows or fallback)
# P&R: local nextpnr-ecp5 (from oss-cad-suite)

PROJ=sdram_min
FPGA_SIZE?=12
CONSTRAINTS=ulx3s_nextpnr.lpf
SYNTH_SCRIPT=synth_docker.ys

# Path to RTL root (relative to this Makefile location)
RTL_ROOT=$(shell cd ../../../.. && pwd)

# Docker image for synthesis (public image with stable GHDL+Yosys)
SYNTH_IMAGE=hdlc/ghdl:yosys
DOCKER_SYNTH=docker run --rm -v "$(RTL_ROOT):/src" -w /src/proj/lattice/ulx3s/sdram_min_trellis_v2 $(SYNTH_IMAGE)

# Default target: local synthesis (Linux/macOS)
all: $(PROJ).bit

# Synthesis with local GHDL+Yosys (oss-cad-suite on Linux/macOS)
$(PROJ).json: $(SYNTH_SCRIPT) Makefile $(wildcard *.vhd)
	yosys -m ghdl $(SYNTH_SCRIPT)

# Docker target: synthesis with Docker container (Windows or fallback)
docker: $(PROJ)_docker.bit

$(PROJ)_docker.json: $(SYNTH_SCRIPT) Makefile $(wildcard *.vhd)
	$(DOCKER_SYNTH) yosys -m ghdl $(SYNTH_SCRIPT)
	mv $(PROJ).json $(PROJ)_docker.json

$(PROJ)_docker.config: $(PROJ)_docker.json $(CONSTRAINTS)
	nextpnr-ecp5 --$(FPGA_SIZE)k --speed 6 --package CABGA381 \
		--json $(PROJ)_docker.json \
		--lpf $(CONSTRAINTS) \
		--lpf-allow-unconstrained \
		--timing-allow-fail \
		--textcfg $(PROJ)_docker.config

$(PROJ)_docker.bit: $(PROJ)_docker.config
	ecppack --compress $(PROJ)_docker.config $(PROJ)_docker.bit

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

prog_docker: $(PROJ)_docker.bit
	fujprog $<

clean:
	rm -f $(PROJ).bit $(PROJ).config $(PROJ).json
	rm -f $(PROJ)_docker.bit $(PROJ)_docker.config $(PROJ)_docker.json
	rm -f *~

.PHONY: all docker prog prog_docker clean
