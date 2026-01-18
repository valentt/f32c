#!/bin/bash
# f32c XRAM SDRAM build script for open-source toolchain
# Usage: ./build.sh [12k|25k|45k|85k]

FPGA_SIZE=${1:-12k}

echo "=== Building f32c XRAM SDRAM for ECP5-${FPGA_SIZE} ==="

# Synthesis
echo "[1/3] Running Yosys synthesis with GHDL..."
yosys -m ghdl synth.ys
if [ $? -ne 0 ]; then
    echo "ERROR: Synthesis failed!"
    exit 1
fi

# Place & Route
echo "[2/3] Running nextpnr place & route..."
nextpnr-ecp5 --${FPGA_SIZE} --package CABGA381 \
    --json f32c_xram.json \
    --lpf ../../../../constraints/ulx3s_v20.lpf \
    --textcfg f32c_xram.config \
    --timing-allow-fail
if [ $? -ne 0 ]; then
    echo "ERROR: Place & route failed!"
    exit 1
fi

# Bitstream
echo "[3/3] Generating bitstream..."
ecppack --compress f32c_xram.config f32c_xram.bit
if [ $? -ne 0 ]; then
    echo "ERROR: Bitstream generation failed!"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
ls -la f32c_xram.bit
echo ""
echo "Program with: fujprog f32c_xram.bit"
