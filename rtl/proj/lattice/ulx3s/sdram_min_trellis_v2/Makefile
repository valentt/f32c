PROJ=sdram_min
all: $(PROJ).bit

FPGA_SIZE=12

CONSTRAINTS=ulx3s_nextpnr.lpf

$(PROJ).json: synth.ys Makefile
	yosys -m ghdl synth.ys

$(PROJ).config: $(PROJ).json
	nextpnr-ecp5 --$(FPGA_SIZE)k --speed 6 --package CABGA381 \
	--json $(PROJ).json \
	--lpf $(CONSTRAINTS) \
	--lpf-allow-unconstrained \
	--textcfg $@

$(PROJ).bit: $(PROJ).config
	ecppack --compress $< $@

prog: $(PROJ).bit
	fujprog $<

clean:
	rm -f $(PROJ).bit $(PROJ).config $(PROJ).json *~
