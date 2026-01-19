# GHDL Feature Requests for Synthesis

Based on experience porting f32c to open-source toolchain (GHDL + Yosys + nextpnr-ecp5).

---

## 1. Optimize Away Unused Array Signals

**Problem:** GHDL synthesizes unused array signals into FFs/LUTs instead of optimizing them away.

**Example:**
```vhdl
type T_icache_bram is array(0 to 1023) of std_logic_vector(46 downto 0);
signal M_i_bram: T_icache_bram;  -- Declared but NEVER used
```

**Impact:**
- Unused 48K-bit array synthesized to 11,000+ FFs
- Caused 8x LUT overhead (21,042 vs 2,493 LUT4)

**Expected:** Dead code elimination should remove unused signals.

**Workaround:** Manually remove unused array declarations from VHDL source.

---

## 2. Better BRAM Inference for Dual-Edge Patterns

**Problem:** Dual-edge BRAM pattern (falling_edge read + rising_edge write) doesn't always map efficiently to ECP5 DP16KD.

**Example:**
```vhdl
process(clk)
begin
    if falling_edge(clk) then
        data_out <= ram(addr_rd);  -- Read on falling edge
    end if;
    if rising_edge(clk) then
        if we then
            ram(addr_wr) <= data_in;  -- Write on rising edge
        end if;
    end if;
end process;
```

**Impact:** Sometimes synthesizes to distributed RAM (TRELLIS_DPR16X4) or LUTs instead of block RAM.

**Expected:** Should infer DP16KD with appropriate clock phase.

**Workaround:** Use explicit bram_true2p_1clk instantiation with single-edge clocking.

---

## 3. Relaxed "Locally Static" Rules for Case/Select

**Problem:** GHDL requires "locally static" choices in case statements, rejecting function calls even when they're compile-time constants.

**Example that fails:**
```vhdl
with conv_integer(addr) select
    output <= '1' when iomap_from(X) to iomap_to(X),  -- ERROR: not locally static
              '0' when others;
```

**Impact:** Requires rewriting case/select as if-elsif-else chains.

**Expected:** Allow constant functions in case choices, or provide clearer error messages with suggestions.

**Workaround:** Replace with conditional assignments:
```vhdl
output <= '1' when (conv_integer(addr) >= iomap_from(X) and
                    conv_integer(addr) <= iomap_to(X)) else '0';
```

---

## 4. Dual-Write Port BRAM Mapping

**Problem:** Dual-write-port BRAM patterns don't map to ECP5 DP16KD (which only supports one write port).

**Example:**
```vhdl
port map (
    we_a => write_a, we_b => write_b,  -- Both ports can write
    ...
)
```

**Impact:** Results in distributed RAM or LUT-based implementation.

**Expected:** Either:
- Warning that pattern is not mappable to target BRAM
- Automatic conversion to muxed single-write pattern

**Workaround:** Manually mux write signals to single port:
```vhdl
signal combined_we: std_logic;
signal combined_addr: std_logic_vector(...);
signal combined_data: std_logic_vector(...);

combined_we <= we_a or we_b;
combined_addr <= addr_b when we_b = '1' else addr_a;
combined_data <= data_b when we_b = '1' else data_a;
```

---

## 5. Warning for Large Inferred Memories

**Request:** Add synthesis warning when large arrays are inferred as distributed RAM/FFs instead of block RAM.

**Example:**
```
Warning: Array 'M_i_bram' (48128 bits) inferred as distributed RAM.
         Consider using block RAM primitive or restructuring code.
```

This would help catch issues like the unused M_i_bram problem earlier.

---

*Created: 2026-01-19*
*Author: Hans Weber (FPGA Agent)*
*Context: f32c FPGA project port to GHDL+Yosys+nextpnr-ecp5*
