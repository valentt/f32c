# f32c XRAM SDRAM - Open Source Toolchain Build

Build f32c with SDRAM support using open-source FPGA toolchain.

## Toolchain Requirements

- **GHDL** with ghdl-yosys-plugin
- **Yosys** with GHDL plugin
- **nextpnr-ecp5**
- **ecppack**

Recommended: Use [oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build)

## Configuration

This build includes:
- 100 MHz CPU clock
- 32 MB SDRAM
- 640x480 HDMI output
- SPI flash boot
- SD card support
- UART serial console

Disabled for initial build (can be enabled later):
- Vector processor
- Audio (PCM, SPDIF)
- ESP32 passthrough detection

## Build Commands

```bash
# Synthesis
yosys -m ghdl synth.ys

# Place & Route (ECP5-12F)
nextpnr-ecp5 --12k --package CABGA381 \
    --json f32c_xram.json \
    --lpf ../../../../constraints/ulx3s_v20.lpf \
    --textcfg f32c_xram.config \
    --timing-allow-fail

# Bitstream
ecppack --compress f32c_xram.config f32c_xram.bit

# Program ULX3S
fujprog f32c_xram.bit
```

## Docker Build

Using f32c-docker:
```bash
docker-compose run --rm fpga-build bash -c "
  cd /workspace/f32c/rtl/proj/lattice/ulx3s/xram_sdram_12f_v2.0_c2_noscripts_trellis && \
  yosys -m ghdl synth.ys && \
  nextpnr-ecp5 --12k --package CABGA381 \
    --json f32c_xram.json \
    --lpf ../../../../constraints/ulx3s_v20.lpf \
    --textcfg f32c_xram.config \
    --timing-allow-fail && \
  ecppack --compress f32c_xram.config f32c_xram.bit
"
```

## Key Differences from Original

1. Top file modified for GHDL compatibility
2. Simplified GPIO (output only for initial build)
3. Some features disabled to reduce complexity
4. Port names match standard ulx3s_v20.lpf

## Troubleshooting

### GHDL inout port errors
The sdram_d and sd_d ports use inOut mode. If GHDL complains, ensure you're using latest GHDL with proper tristate support.

### Timing failures
Use `--timing-allow-fail` for initial builds. Optimize later with:
- `--seed N` - try different placement seeds
- Reduce clock frequency in generics

## License

BSD 2-Clause (same as f32c)
