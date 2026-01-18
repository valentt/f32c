-- f32c XRAM SDRAM for ULX3S - Open-source toolchain version
-- Modified for GHDL + Yosys + nextpnr-ecp5 compatibility
-- Based on top_ulx3s_12f_xram_sdram.vhd by EMARD
-- Port names match ulx3s_v20.lpf

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.math_real.all;

use work.f32c_pack.all;

use work.boot_block_pack.all;
use work.boot_sio_mi32el.all;
use work.boot_sio_mi32eb.all;
use work.boot_sio_rv32el.all;
use work.boot_rom_mi32el.all;

library ecp5u;
use ecp5u.components.all;

entity ulx3s_xram_sdram_vector is
  generic
  (
    -- ISA: either ARCH_MI32 or ARCH_RV32
    C_arch: integer := ARCH_MI32;
    C_debug: boolean := false;

    -- Main clock: 25/78/100 MHz
    C_clk_freq: integer := 100;

    -- SoC configuration options
    C_boot_rom: boolean := true;
    C_xboot_rom: boolean := false;
    C_bram_size: integer := 2;
    C_bram_const_init: boolean := true;
    C_boot_write_protect: boolean := true;
    C_boot_rom_data_bits: integer := 32;
    C_boot_spi: boolean := true;
    C_xram_base: std_logic_vector(31 downto 28) := x"8";
    C_PC_mask: std_logic_vector(31 downto 0) := x"81ffffff";
    C_cached_addr_bits: integer := 25;
    C_acram: boolean := false;
    C_acram_wait_cycles: integer := 3;
    C_acram_emu_kb: integer := 128;
    C_sdram: boolean := true;
    C_sdram_wait_cycles: integer := 2;
    C_icache_size: integer := 8;
    C_dcache_size: integer := 8;
    C_branch_prediction: boolean := true;
    C_sio: integer := 1;  -- Simplified: 1 serial port
    C_spi: integer := 2;  -- Simplified: flash + SD card
    C_spi_fixed_speed: std_logic_vector := "11";
    C_simple_io: boolean := true;
    C_gpio: integer := 32;  -- Simplified
    C_gpio_pullup: boolean := false;
    C_gpio_adc: integer := 0;
    C_timer: boolean := true;
    C_pcm: boolean := false;  -- Disabled for initial build
    C_synth: boolean := false;
    C_dacpwm: boolean := false;
    C_spdif: boolean := false;
    C_cw_simple_out: integer := -1;  -- Disabled

    C_passthru_autodetect: boolean := false;  -- Disabled for simplicity

    C_vector: boolean := false;  -- Disabled for initial build

    -- video parameters
    C_dvid_ddr: boolean := true;
    C_video_mode: integer := 1;
    C_shift_clock_synchronizer: boolean := true;

    C_vgahdmi: boolean := true;
    C_vgahdmi_fifo_data_width: integer range 8 to 32 := 16;
    C_vgahdmi_fifo_burst_max_bits: integer range 0 to 8 := 8;
    C_vgahdmi_fifo_fast_ram: boolean := true;
    C_vgahdmi_cache_size: integer := 0;
    C_vgahdmi_cache_use_i: boolean := false;
    C_compositing2_write_while_reading: boolean := true;

    C_vgatext: boolean := false
  );
  port
  (
    clk_25mhz: in std_logic;

    -- UART0 (FTDI USB slave serial)
    ftdi_rxd: out std_logic;
    ftdi_txd: in std_logic;

    -- SDRAM interface (active directly - no inout wrapper needed)
    sdram_clk: out std_logic;
    sdram_cke: out std_logic;
    sdram_csn: out std_logic;
    sdram_rasn: out std_logic;
    sdram_casn: out std_logic;
    sdram_wen: out std_logic;
    sdram_a: out std_logic_vector(12 downto 0);
    sdram_ba: out std_logic_vector(1 downto 0);
    sdram_dqm: out std_logic_vector(1 downto 0);
    sdram_d: inout std_logic_vector(15 downto 0);

    -- Onboard blinky
    led: out std_logic_vector(7 downto 0);
    btn: in std_logic_vector(6 downto 0);
    sw: in std_logic_vector(3 downto 0);

    -- GPIO - directly as output for basic testing
    gp: out std_logic_vector(27 downto 0);
    gn: out std_logic_vector(27 downto 0);

    -- Digital Video (directly as output)
    gpdi_dp: out std_logic_vector(3 downto 0);
    gpdi_dn: out std_logic_vector(3 downto 0);

    -- Flash ROM (directly as in/out)
    flash_miso: in std_logic;
    flash_mosi: out std_logic;
    flash_csn: out std_logic;
    flash_holdn: out std_logic := '1';
    flash_wpn: out std_logic := '1';

    -- SD card
    sd_cmd: out std_logic;
    sd_d: inOut std_logic_vector(3 downto 0);
    sd_clk: out std_logic;
    sd_cdn: in std_logic;
    sd_wp: in std_logic
  );
end;

architecture Behavioral of ulx3s_xram_sdram_vector is
  function ceil_log2(x: integer) return integer is
  begin
      return integer(ceil((log2(real(x)-1.0E-6))-1.0E-6));
  end ceil_log2;

  signal clk: std_logic;
  signal clk_pixel_shift, clk_pixel: std_logic;
  signal ram_en: std_logic;
  signal ram_byte_we: std_logic_vector(3 downto 0) := (others => '0');
  signal ram_address: std_logic_vector(31 downto 0) := (others => '0');
  signal ram_data_write: std_logic_vector(31 downto 0) := (others => '0');
  signal ram_data_read: std_logic_vector(31 downto 0) := (others => '0');
  signal ram_ready: std_logic;
  signal dvid_crgb: std_logic_vector(7 downto 0);
  signal ddr_d: std_logic_vector(3 downto 0);

  signal S_reset: std_logic := '0';
  signal xdma_addr: std_logic_vector(29 downto 2) := ('0', others => '0');
  signal xdma_strobe: std_logic := '0';
  signal xdma_data_ready: std_logic := '0';
  signal xdma_write: std_logic := '0';
  signal xdma_byte_sel: std_logic_vector(3 downto 0) := (others => '1');
  signal xdma_data_in: std_logic_vector(31 downto 0) := (others => '-');
  signal S_rom_reset, S_rom_next_data: std_logic;
  signal S_rom_data: std_logic_vector(C_boot_rom_data_bits-1 downto 0);
  signal S_rom_valid: std_logic;

  signal S_rxd, S_txd: std_logic;
  signal S_f32c_sd_csn, S_f32c_sd_clk, S_f32c_sd_miso, S_f32c_sd_mosi: std_logic;
  signal S_flash_csn, S_flash_clk: std_logic;

  -- GPIO internal signals
  signal S_gpio: std_logic_vector(127 downto 0);
  signal S_simple_out: std_logic_vector(31 downto 0);

  component ODDRX1F
    port(D0, D1, SCLK, RST: in std_logic; Q: out std_logic);
  end component;

  component OLVDS
    port(A: in std_logic; Z, ZN: out std_logic);
  end component;

begin
  -- Clock generation for 100MHz CPU, 640x480 video
  ddr_640x480_100MHz: if C_clk_freq=100 and (C_video_mode=0 or C_video_mode=1) generate
  clk_100M: entity work.clk_25_100_125_25
    port map(
      CLKI        =>  clk_25mhz,
      CLKOP       =>  clk_pixel_shift,   -- 125 MHz
      CLKOS       =>  open,
      CLKOS2      =>  clk_pixel,         -- 25 MHz
      CLKOS3      =>  clk                -- 100 MHz CPU
     );
  end generate;

  -- Simple serial passthrough
  S_rxd <= ftdi_txd;
  ftdi_rxd <= S_txd;

  -- SD card directly connected
  sd_d(3) <= S_f32c_sd_csn;
  sd_clk <= S_f32c_sd_clk;
  S_f32c_sd_miso <= sd_d(0);
  sd_cmd <= S_f32c_sd_mosi;
  sd_d(2 downto 1) <= (others => '1');

  -- Main SoC
  glue_xram: entity work.glue_xram
  generic map (
    C_arch => C_arch,
    C_clk_freq => C_clk_freq,
    C_boot_rom => C_boot_rom,
    C_bram_size => C_bram_size,
    C_bram_const_init => C_bram_const_init,
    C_boot_write_protect => C_boot_write_protect,
    C_boot_spi => C_boot_spi,
    C_branch_prediction => C_branch_prediction,
    C_PC_mask => C_PC_mask,
    C_acram => C_acram,
    C_acram_wait_cycles => C_acram_wait_cycles,
    C_sdram => C_sdram,
    C_sdram_clock_range => 2,
    C_sdram_ras => C_sdram_wait_cycles,
    C_sdram_cas => C_sdram_wait_cycles,
    C_sdram_pre => C_sdram_wait_cycles,
    C_sdram_address_width => 24,
    C_sdram_column_bits => 9,
    C_sdram_startup_cycles => 12000,
    C_sdram_cycles_per_refresh => 1524,
    C_icache_size => C_icache_size,
    C_dcache_size => C_dcache_size,
    C_cached_addr_bits => C_cached_addr_bits,
    C_xdma => C_xboot_rom,
    C_xram_base => C_xram_base,
    C_debug => C_debug,
    C_sio => C_sio,
    C_spi => C_spi,
    C_spi_fixed_speed => C_spi_fixed_speed,
    C_gpio => C_gpio,
    C_gpio_pullup => C_gpio_pullup,
    C_gpio_adc => C_gpio_adc,
    C_timer => C_timer,
    C_pcm => C_pcm,
    C_synth => C_synth,
    C_dacpwm => C_dacpwm,
    C_spdif => C_spdif,
    C_cw_simple_out => C_cw_simple_out,
    C_vector => C_vector,
    C_dvid_ddr => C_dvid_ddr,
    C_shift_clock_synchronizer => C_shift_clock_synchronizer,
    C_compositing2_write_while_reading => C_compositing2_write_while_reading,
    C_vgahdmi => C_vgahdmi,
    C_vgahdmi_mode => C_video_mode,
    C_vgahdmi_cache_size => C_vgahdmi_cache_size,
    C_vgahdmi_fifo_data_width => C_vgahdmi_fifo_data_width,
    C_vgahdmi_fifo_burst_max_bits => C_vgahdmi_fifo_burst_max_bits,
    C_vgatext => C_vgatext
  )
  port map (
    clk => clk,
    clk_pixel => clk_pixel,
    clk_pixel_shift => clk_pixel_shift,
    reset => S_reset,
    sio_rxd(0) => S_rxd,
    sio_txd(0) => S_txd,
    sio_break(0) => open,

    spi_ss(0) => S_flash_csn,
    spi_ss(1) => S_f32c_sd_csn,
    spi_sck(0) => S_flash_clk,
    spi_sck(1) => S_f32c_sd_clk,
    spi_mosi(0) => flash_mosi,
    spi_mosi(1) => S_f32c_sd_mosi,
    spi_miso(0) => flash_miso,
    spi_miso(1) => S_f32c_sd_miso,

    gpio(127 downto 0) => S_gpio,
    simple_out(31 downto 0) => S_simple_out,
    simple_out(7 downto 0) => led(7 downto 0),
    simple_in(19 downto 16) => sw,
    simple_in(6 downto 0) => btn,
    simple_in(31 downto 20) => (others => '0'),
    simple_in(15 downto 7) => (others => '0'),

    -- SDRAM interface
    sdram_addr => sdram_a,
    sdram_data(15 downto 0) => sdram_d,
    sdram_ba => sdram_ba,
    sdram_dqm(1 downto 0) => sdram_dqm,
    sdram_ras => sdram_rasn,
    sdram_cas => sdram_casn,
    sdram_cke => sdram_cke,
    sdram_clk => sdram_clk,
    sdram_we => sdram_wen,
    sdram_cs => sdram_csn,

    -- ACRAM emulation
    acram_en => ram_en,
    acram_addr(29 downto 2) => ram_address(29 downto 2),
    acram_byte_we(3 downto 0) => ram_byte_we(3 downto 0),
    acram_data_rd(31 downto 0) => ram_data_read(31 downto 0),
    acram_data_wr(31 downto 0) => ram_data_write(31 downto 0),
    acram_ready => ram_ready,

    -- exposed DMA
    xdma_addr => xdma_addr,
    xdma_strobe => xdma_strobe,
    xdma_write => '1',
    xdma_byte_sel => "1111",
    xdma_data_in => xdma_data_in,
    xdma_data_ready => xdma_data_ready,

    -- DVID output
    dvid_clock => dvid_crgb(7 downto 6),
    dvid_red   => dvid_crgb(5 downto 4),
    dvid_green => dvid_crgb(3 downto 2),
    dvid_blue  => dvid_crgb(1 downto 0)
  );

  -- DDR HDMI output with differential buffers
  G_dvid_ddr: if C_dvid_ddr generate
    G_ddr_diff: for i in 0 to 3 generate
      gpdi_ddr: ODDRX1F port map(D0=>dvid_crgb(2*i), D1=>dvid_crgb(2*i+1), Q=>ddr_d(i), SCLK=>clk_pixel_shift, RST=>'0');
      gpdi_diff: OLVDS port map(A => ddr_d(i), Z => gpdi_dp(i), ZN => gpdi_dn(i));
    end generate;
  end generate;

  -- Flash clock generation
  flash_clock: entity work.ecp5_flash_clk
  port map
  (
    flash_csn => '0',  -- Always enabled
    flash_clk => S_flash_clk
  );
  flash_csn <= S_flash_csn;

  -- GPIO directly output (simplified - no bidirectional for now)
  gp <= S_gpio(27 downto 0);
  gn <= S_gpio(59 downto 32);

end Behavioral;
