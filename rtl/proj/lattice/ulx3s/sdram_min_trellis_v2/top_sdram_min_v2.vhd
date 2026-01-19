-- Modified top_sdram_min for GHDL + Yosys open-source toolchain
-- Based on top_ulx3s_12f_xram_sdram_ghdl.vhd approach
-- NO library ecp5u - use component declarations instead

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use work.f32c_pack.all;

entity top_sdram is
    generic (
	C_arch: natural := ARCH_MI32;
	C_clk_freq: natural := 84;
	C_icache_size: natural := 8;
	C_dcache_size: natural := 8
    );
    port (
	clk_25m: in std_logic;

	-- SDRAM
	sdram_clk: out std_logic;
	sdram_cke: out std_logic;
	sdram_csn: out std_logic;
	sdram_rasn: out std_logic;
	sdram_casn: out std_logic;
	sdram_wen: out std_logic;
	sdram_a: out std_logic_vector (12 downto 0);
	sdram_ba: out std_logic_vector(1 downto 0);
	sdram_dqm: out std_logic_vector(1 downto 0);
	sdram_d: inout std_logic_vector (15 downto 0);

	-- On-board simple IO
	led: out std_logic_vector(7 downto 0);
	btn_pwr, btn_f1, btn_f2: in std_logic;
	btn_up, btn_down, btn_left, btn_right: in std_logic;
	sw: in std_logic_vector(3 downto 0);

	-- GPIO
	gp: inOut std_logic_vector(27 downto 0);
	gn: inOut std_logic_vector(27 downto 0);

	-- Audio jack 3.5mm
	p_tip: inOut std_logic_vector(3 downto 0);
	p_ring: inOut std_logic_vector(3 downto 0);
	p_ring2: inOut std_logic_vector(3 downto 0);

	-- SIO0 (FTDI)
	rs232_tx: out std_logic;
	rs232_rx: in std_logic;

	-- Digital Video (differential outputs)
	gpdi_dp, gpdi_dn: out std_logic_vector(3 downto 0);

	-- i2c shared for digital video and RTC
	gpdi_scl, gpdi_sda: inOut std_logic;

	-- SPI flash (SPI #0)
	flash_so: inout std_logic;
	flash_si: inout std_logic;
	flash_cen: out std_logic;
	flash_holdn, flash_wpn: out std_logic := '1';

	-- SD card (SPI #1)
	sd_cmd: inOut std_logic;
	sd_clk: out std_logic;
	sd_d: inOut std_logic_vector(3 downto 0);
	sd_cdn: in std_logic;
	sd_wp: in std_logic;

	-- ADC MAX11123 (SPI #2)
	adc_csn: out std_logic;
	adc_sclk: out std_logic;
	adc_mosi: inout std_logic;
	adc_miso: inout std_logic;

	-- PCB antenna
	ant: out std_logic;

	-- '1' = power off
	shutdown: out std_logic := '0'
    );
end top_sdram;

architecture x of top_sdram is
    signal clk, pll_lock: std_logic;
    signal clk_112m5, clk_96m43, clk_84m34: std_logic;
    signal reset: std_logic;
    signal sio_break: std_logic;
    signal flash_sck: std_logic;
    signal flash_csn: std_logic;

    signal R_simple_in: std_logic_vector(19 downto 0);

    -- PLL clock outputs
    signal S_clocks: std_logic_vector(3 downto 0);

    -- Component declaration for ODDRX1F (ECP5 DDR output primitive)
    component ODDRX1F
        port (D0, D1, SCLK, RST: in std_logic; Q: out std_logic);
    end component;

begin
    -- f32c SoC
    I_top: entity work.glue_sdram_min
    generic map (
	C_arch => C_arch,
	C_clk_freq => C_clk_freq,
	C_icache_size => C_icache_size,
	C_dcache_size => C_dcache_size,
	C_spi => 3,
	C_simple_out => 8,
	C_simple_in => 20,
	C_debug => false
    )
    port map (
	clk => clk,
	reset => reset,
	sdram_clk => open,  -- We generate DDR clock separately
	sdram_cke => sdram_cke,
	sdram_cs => sdram_csn,
	sdram_we => sdram_wen,
	sdram_ba => sdram_ba,
	sdram_dqm => sdram_dqm,
	sdram_ras => sdram_rasn,
	sdram_cas => sdram_casn,
	sdram_addr => sdram_a,
	sdram_data => sdram_d,
	sio_rxd(0) => rs232_rx,
	sio_txd(0) => rs232_tx,
	sio_break(0) => sio_break,
	simple_in => R_simple_in,
	simple_out => led,
	spi_ss(0) => flash_csn,
	spi_ss(1) => sd_d(3),
	spi_ss(2) => adc_csn,
	spi_sck(0) => flash_sck,
	spi_sck(1) => sd_clk,
	spi_sck(2) => adc_sclk,
	spi_mosi(0) => flash_si,
	spi_mosi(1) => sd_cmd,
	spi_mosi(2) => adc_mosi,
	spi_miso(0) => flash_so,
	spi_miso(1) => sd_d(0),
	spi_miso(2) => adc_miso
    );
    R_simple_in <= sw & x"00" & '0' & not btn_pwr & btn_f2 & btn_f1
      & btn_up & btn_down & btn_left & btn_right when rising_edge(clk);

    -- SDRAM clock via DDR output (generates 180 degree phase shifted clock)
    I_sdram_clk: ODDRX1F
    port map (D0 => '0', D1 => '1', SCLK => clk, RST => '0', Q => sdram_clk);

    -- SPI flash clock has to be routed through ECP5-specific USRMCLK primitive
    I_flash_clk: entity work.ecp5_flash_clk
    port map (
	flash_csn => flash_csn,
	flash_clk => flash_sck
    );
    flash_cen <= flash_csn;

    -- PLL using ecp5pll parametric module
    I_pll: entity work.ecp5pll
    generic map (
	in_Hz    => 25000000,
	out0_Hz  => 112500000,  -- 112.5 MHz
	out1_Hz  => 96428571,   -- ~96.43 MHz
	out2_Hz  => 84375000    -- ~84.375 MHz
    )
    port map (
	clk_i  => clk_25m,
	clk_o  => S_clocks,
	locked => pll_lock
    );

    clk_112m5  <= S_clocks(0);
    clk_96m43  <= S_clocks(1);
    clk_84m34  <= S_clocks(2);

    clk <= clk_112m5 when C_clk_freq = 112
      else clk_96m43 when C_clk_freq = 96
      else clk_84m34 when C_clk_freq = 84
      else '0';
    reset <= not pll_lock or sio_break;
end x;
