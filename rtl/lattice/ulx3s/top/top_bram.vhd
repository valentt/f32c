--
-- Copyright (c) 2015, 2016 Marko Zec, University of Zagreb
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
--
-- Modified for open-source toolchain (GHDL + Yosys + nextpnr)
-- Hans Weber, 2026-01-18

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use work.f32c_pack.all;

entity glue is
    generic (
	C_arch: integer := ARCH_MI32; -- either ARCH_MI32 or ARCH_RV32
	C_big_endian: boolean := false;
	C_mult_enable: boolean := true;
	C_mul_reg: boolean := false;
	C_debug: boolean := false;

	C_clk_freq: integer := 100;

	-- SoC configuration options
	C_bram_size: integer := 32;
	C_sio: integer := 1;
	C_spi: integer := 0;  -- disabled for BRAM-only build
	C_gpio: integer := 0;
	C_simple_io: boolean := true;
	C_timer: boolean := true
    );
    port (
	clk_25mhz: in std_logic;
	ftdi_rxd: out std_logic;  -- FPGA TX to FTDI
	ftdi_txd: in std_logic;   -- FPGA RX from FTDI
	led: out std_logic_vector(7 downto 0);
	btn: in std_logic_vector(6 downto 0);  -- 0=pwr,1=f1,2=f2,3=up,4=down,5=left,6=right
	sw: in std_logic_vector(3 downto 0);
	ftdi_txden: out std_logic
    );
end glue;

architecture x of glue is
    signal clk, pll_lock: std_logic;
    signal pll_clk: std_logic_vector(3 downto 0);
    signal reset: std_logic;
    signal sio_break: std_logic;

    signal R_simple_in: std_logic_vector(19 downto 0);
    signal open_out: std_logic_vector(31 downto 8);

begin
    clk <= pll_clk(0);
    -- generic BRAM glue
    glue_bram: entity work.glue_bram
    generic map (
	C_arch => C_arch,
	C_big_endian => C_big_endian,
	C_mult_enable => C_mult_enable,
	C_mul_reg => C_mul_reg,
	C_clk_freq => C_clk_freq,
	C_bram_size => C_bram_size,
	C_debug => C_debug,
	C_sio => C_sio,
	C_spi => C_spi,
	C_gpio => C_gpio,
	C_timer => C_timer
    )
    port map (
	clk => clk,
	sio_txd(0) => ftdi_rxd,
	sio_rxd(0) => ftdi_txd,
	sio_break(0) => sio_break,
	simple_out(31 downto 8) => open_out,
	simple_out(7 downto 0) => led,
	simple_in(31 downto 20) => (others => '-'),
	simple_in(19 downto 0) => R_simple_in,
	spi_miso => (others => '0')
    );
    R_simple_in <= sw & x"00" & '0' & not btn(0) & btn(2) & btn(1)
      & btn(3) & btn(4) & btn(5) & btn(6) when rising_edge(clk);

    I_pll: entity work.ecp5pll
    generic map (
	in_hz => 25000000,
	out0_hz => C_clk_freq * 1000000
    )
    port map (
	clk_i => clk_25mhz,
	clk_o => pll_clk,
	locked => pll_lock
    );

    reset <= not pll_lock or sio_break;

end x;
