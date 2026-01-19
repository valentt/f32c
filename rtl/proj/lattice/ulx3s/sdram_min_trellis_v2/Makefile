# f32c sdram_min - Open-source FPGA Toolchain Build
# Target: ULX3S (LFE5U-12F)
# Tools: GHDL + Yosys + nextpnr-ecp5 + ecppack

DOCKER_IMAGE = f32c-patched:latest
PROJECT_DIR = /projects/f32c-valent/rtl/proj/lattice/ulx3s/sdram_min_trellis_v2
MOUNT = -v $(shell cd ../../../../../.. && pwd):/projects

# Target device
DEVICE = 12k
PACKAGE = CABGA381
SPEED = 6

# Output files
JSON = sdram_min.json
CONFIG = sdram_min.config
BITSTREAM = sdram_min.bit

.PHONY: all synth pnr bit clean prog

all: $(BITSTREAM)

# Synthesis with GHDL + Yosys
synth: $(JSON)

$(JSON): synth.ys
	docker run --rm $(MOUNT) -w $(PROJECT_DIR) $(DOCKER_IMAGE) \
		yosys -m ghdl synth.ys

# Place and Route with nextpnr-ecp5
pnr: $(CONFIG)

$(CONFIG): $(JSON) ulx3s_nextpnr.lpf
	docker run --rm $(MOUNT) -w $(PROJECT_DIR) $(DOCKER_IMAGE) \
		nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
		--json $(JSON) --lpf ulx3s_nextpnr.lpf --lpf-allow-unconstrained \
		--textcfg $(CONFIG)

# Bitstream generation with ecppack
bit: $(BITSTREAM)

$(BITSTREAM): $(CONFIG)
	docker run --rm $(MOUNT) -w $(PROJECT_DIR) $(DOCKER_IMAGE) \
		ecppack --compress --input $(CONFIG) --bit $(BITSTREAM)

# Program ULX3S via fujprog
prog: $(BITSTREAM)
	fujprog $(BITSTREAM)

# Clean generated files
clean:
	rm -f $(JSON) $(CONFIG) $(BITSTREAM)

# Help
help:
	@echo "f32c sdram_min Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all    - Build bitstream (default)"
	@echo "  synth  - Run synthesis only"
	@echo "  pnr    - Run place and route"
	@echo "  bit    - Generate bitstream"
	@echo "  prog   - Program ULX3S board"
	@echo "  clean  - Remove generated files"
	@echo ""
	@echo "Requirements:"
	@echo "  - Docker with $(DOCKER_IMAGE)"
	@echo "  - fujprog for programming"
