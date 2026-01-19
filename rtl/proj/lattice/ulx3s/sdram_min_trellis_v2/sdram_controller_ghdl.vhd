--
-- SDRAM Controller Wrapper for GHDL/Yosys Compatibility
--
-- Copyright (c) 2026 Hans Weber
--
-- This wrapper splits the bidirectional sdram_port_array record into
-- separate input and output signals to avoid the Yosys flatten error:
-- "Cell port sdram.mpbus is driving constant bits"
--
-- The original sdram_mz.vhd uses inOut record port which causes issues
-- when some fields are constant-driven (e.g., instruction port's write='0')
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_controller_ghdl is
    generic (
        C_ports: integer;
        C_prio_port: integer := -1;
        C_ras: integer range 2 to 3 := 2;
        C_cas: integer range 2 to 3 := 2;
        C_pre: integer range 2 to 3 := 2;
        C_clock_range: integer range 0 to 2 := 2;
        sdram_address_width: natural;
        sdram_column_bits: natural;
        sdram_startup_cycles: natural;
        cycles_per_refresh: natural
    );
    port (
        clk: in STD_LOGIC;
        reset: in STD_LOGIC;

        -- Port 0 (data port) - from CPU
        port0_addr: in std_logic_vector(31 downto 2);
        port0_data_in: in std_logic_vector(31 downto 0);
        port0_byte_sel: in std_logic_vector(3 downto 0);
        port0_addr_strobe: in std_logic;
        port0_burst_len: in std_logic_vector(2 downto 0);
        port0_write: in std_logic;
        -- Port 0 - to CPU
        port0_data_out: out std_logic_vector(31 downto 0);
        port0_data_ready: out std_logic;

        -- Port 1 (instruction port) - from CPU
        port1_addr: in std_logic_vector(31 downto 2);
        port1_data_in: in std_logic_vector(31 downto 0);
        port1_byte_sel: in std_logic_vector(3 downto 0);
        port1_addr_strobe: in std_logic;
        port1_burst_len: in std_logic_vector(2 downto 0);
        port1_write: in std_logic;
        -- Port 1 - to CPU
        port1_data_out: out std_logic_vector(31 downto 0);
        port1_data_ready: out std_logic;

        -- Snoop interface
        snoop_addr: out std_logic_vector(31 downto 2);
        snoop_cycle: out std_logic;

        -- SDRAM signals
        sdram_clk: out STD_LOGIC;
        sdram_cke: out STD_LOGIC;
        sdram_cs: out STD_LOGIC;
        sdram_ras: out STD_LOGIC;
        sdram_cas: out STD_LOGIC;
        sdram_we: out STD_LOGIC;
        sdram_dqm: out STD_LOGIC_VECTOR(1 downto 0);
        sdram_addr: out STD_LOGIC_VECTOR(12 downto 0);
        sdram_ba: out STD_LOGIC_VECTOR(1 downto 0);
        sdram_data: inout STD_LOGIC_VECTOR(15 downto 0)
    );
end sdram_controller_ghdl;

architecture Behavioral of sdram_controller_ghdl is
    -- From page 37 of MT48LC16M16A2 datasheet
    constant CMD_UNSELECTED    : std_logic_vector(3 downto 0) := "1000";
    constant CMD_NOP           : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE        : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ          : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE         : std_logic_vector(3 downto 0) := "0100";
    constant CMD_TERMINATE     : std_logic_vector(3 downto 0) := "0110";
    constant CMD_PRECHARGE     : std_logic_vector(3 downto 0) := "0010";
    constant CMD_REFRESH       : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MODE_REG : std_logic_vector(3 downto 0) := "0000";

    constant MODE_REG_CAS_2    : std_logic_vector(12 downto 0) :=
      "000" & "0" & "00" & "010" & "0" & "001";
    constant MODE_REG_CAS_3    : std_logic_vector(12 downto 0) :=
      "000" & "0" & "00" & "011" & "0" & "001";

    signal iob_command     : std_logic_vector(3 downto 0) := CMD_NOP;
    signal iob_address     : std_logic_vector(12 downto 0) := (others => '0');
    signal iob_data        : std_logic_vector(15 downto 0) := (others => '0');
    signal iob_dqm         : std_logic_vector(1 downto 0) := (others => '0');
    signal iob_cke         : std_logic := '0';
    signal iob_bank        : std_logic_vector(1 downto 0) := (others => '0');

    attribute IOB: string;
    attribute IOB of iob_command: signal is "true";
    attribute IOB of iob_address: signal is "true";
    attribute IOB of iob_dqm    : signal is "true";
    attribute IOB of iob_cke    : signal is "true";
    attribute IOB of iob_bank   : signal is "true";
    attribute IOB of iob_data   : signal is "true";

    signal iob_data_next: std_logic_vector(15 downto 0) := (others => '0');
    signal R_from_sdram_prev, R_from_sdram: std_logic_vector(15 downto 0);
    signal R_ready_out: std_logic_vector(C_ports - 1 downto 0);
    attribute IOB of R_from_sdram: signal is "true";

    type fsm_state is (
        s_startup,
        s_idle_in_6, s_idle_in_5, s_idle_in_4,
        s_idle_in_3, s_idle_in_2, s_idle_in_1,
        s_idle,
        s_open_in_2, s_open_in_1,
        s_write_1, s_write_2, s_write_3,
        s_read_1, s_read_2, s_read_3, s_read_4,
        s_precharge
    );

    signal state: fsm_state := s_startup;
    attribute FSM_ENCODING: string;
    attribute FSM_ENCODING of state: signal is "ONE-HOT";

    constant startup_refresh_max   : unsigned(13 downto 0) := (others => '1');
    signal   startup_refresh_count : unsigned(13 downto 0) := startup_refresh_max - to_unsigned(sdram_startup_cycles,14);

    signal pending_refresh: std_logic := '0';
    signal forcing_refresh: std_logic := '0';

    signal addr_row: std_logic_vector(12 downto 0) := (others => '0');
    signal addr_col: std_logic_vector(12 downto 0) := (others => '0');
    signal addr_bank: std_logic_vector(1 downto 0) := (others => '0');

    signal dqm_sr: std_logic_vector(3 downto 0) := (others => '1');

    signal save_wr: std_logic := '0';
    signal save_row: std_logic_vector(12 downto 0);
    signal save_bank: std_logic_vector(1 downto 0);
    signal save_col: std_logic_vector(12 downto 0);
    signal save_data_in: std_logic_vector(31 downto 0);
    signal save_byte_enable: std_logic_vector(3 downto 0);
    signal save_burst_len: std_logic_vector(2 downto 0);

    signal ready_for_new: std_logic := '0';
    signal can_back_to_back: std_logic := '0';

    signal iob_dq_hiz: std_logic := '1';

    signal data_ready_delay:
      std_logic_vector(C_clock_range / 2 + C_cas + 1 downto 0);
    signal read_done: boolean;

    constant start_of_col: natural := 0;
    constant end_of_col: natural := sdram_column_bits-2;
    constant start_of_bank: natural := sdram_column_bits-1;
    constant end_of_bank: natural := sdram_column_bits;
    constant start_of_row: natural := sdram_column_bits+1;
    constant end_of_row: natural := sdram_address_width-2;
    constant prefresh_cmd: natural := 10;

    -- Bus interface signals
    signal addr_strobe: std_logic;
    signal write_sig: std_logic;
    signal byte_sel: std_logic_vector(3 downto 0);
    signal addr: std_logic_vector(31 downto 0);
    signal data_in: std_logic_vector(31 downto 0);
    signal burst_len: std_logic_vector(2 downto 0);

    -- Arbiter registers
    signal R_cur_port, R_next_port: integer range 0 to (C_ports - 1);

    -- Arbiter internal signals
    signal next_port: integer;

    -- Port arrays for arbiter (replacing the record)
    type addr_array_t is array(0 to C_ports-1) of std_logic_vector(31 downto 2);
    type data_array_t is array(0 to C_ports-1) of std_logic_vector(31 downto 0);
    type byte_sel_array_t is array(0 to C_ports-1) of std_logic_vector(3 downto 0);
    type burst_len_array_t is array(0 to C_ports-1) of std_logic_vector(2 downto 0);

    signal port_addr: addr_array_t;
    signal port_data_in: data_array_t;
    signal port_byte_sel: byte_sel_array_t;
    signal port_addr_strobe: std_logic_vector(C_ports-1 downto 0);
    signal port_burst_len: burst_len_array_t;
    signal port_write: std_logic_vector(C_ports-1 downto 0);

begin
    -- Map external ports to internal arrays
    port_addr(0) <= port0_addr;
    port_data_in(0) <= port0_data_in;
    port_byte_sel(0) <= port0_byte_sel;
    port_addr_strobe(0) <= port0_addr_strobe;
    port_burst_len(0) <= port0_burst_len;
    port_write(0) <= port0_write;

    port_addr(1) <= port1_addr;
    port_data_in(1) <= port1_data_in;
    port_byte_sel(1) <= port1_byte_sel;
    port_addr_strobe(1) <= port1_addr_strobe;
    port_burst_len(1) <= port1_burst_len;
    port_write(1) <= port1_write;

    -- Inbound multiport mux
    addr_strobe <= port_addr_strobe(R_next_port);
    write_sig <= port_write(R_next_port);
    byte_sel <= port_byte_sel(R_next_port);
    addr(29 downto 0) <= port_addr(R_next_port);
    addr(31 downto 30) <= "00";
    data_in <= port_data_in(R_next_port);
    burst_len <= port_burst_len(R_next_port);

    -- Outbound demux
    port0_data_ready <= R_ready_out(0);
    port0_data_out <= R_from_sdram & R_from_sdram_prev;
    port1_data_ready <= R_ready_out(1);
    port1_data_out <= R_from_sdram & R_from_sdram_prev;

    pending_refresh <= startup_refresh_count(11);
    forcing_refresh <= startup_refresh_count(12);

    addr_row(end_of_row-start_of_row downto 0) <= addr(end_of_row downto start_of_row);
    addr_bank <= addr(end_of_bank downto start_of_bank);
    addr_col(sdram_column_bits-1 downto 0) <= addr(end_of_col downto start_of_col) & '0';

    sdram_clk <= not clk;

    sdram_cke <= iob_cke;
    sdram_CS <= iob_command(3);
    sdram_RAS <= iob_command(2);
    sdram_CAS <= iob_command(1);
    sdram_WE <= iob_command(0);
    sdram_dqm <= iob_dqm;
    sdram_ba <= iob_bank;
    sdram_addr <= iob_address;

    sdram_data <= iob_data when iob_dq_hiz = '0' else (others => 'Z');

    -- Arbiter: round-robin port selection
    process(port_addr_strobe, R_cur_port)
        variable i, j, t, n: integer;
    begin
        t := R_cur_port;
        for i in 0 to (C_ports - 1) loop
            for j in 1 to C_ports loop
                if R_cur_port = i then
                    n := (i + j) mod C_ports;
                    if port_addr_strobe(n) = '1' and n /= C_prio_port then
                        t := n;
                        exit;
                    end if;
                end if;
            end loop;
        end loop;
        next_port <= t;
    end process;

    capture_proc: process(clk)
    begin
        if C_clock_range = 1 and falling_edge(clk) then
            R_from_sdram <= sdram_data;
            R_from_sdram_prev <= R_from_sdram;
        end if;
        if C_clock_range /= 1 and rising_edge(clk) then
            R_from_sdram <= sdram_data;
            R_from_sdram_prev <= R_from_sdram;
        end if;
    end process;

    main_proc: process(clk)
    begin
        if rising_edge(clk) then
            R_next_port <= next_port;

            iob_command <= CMD_NOP;
            iob_address <= (others => '0');
            iob_bank <= (others => '0');

            startup_refresh_count <= startup_refresh_count+1;

            if data_ready_delay(3 downto 1) = "001" then
                read_done <= true;
            end if;
            data_ready_delay <= '0' & data_ready_delay(data_ready_delay'high downto 1);
            iob_dqm <= dqm_sr(1 downto 0);
            dqm_sr <= "11" & dqm_sr(dqm_sr'high downto 2);

            R_ready_out <= (others => '0');
            R_ready_out(R_cur_port) <= data_ready_delay(1);
            if ready_for_new = '1' and addr_strobe = '1'
              and read_done and R_ready_out(R_next_port) = '0' then
                R_cur_port <= R_next_port;
                if save_bank = addr_bank and save_row = addr_row then
                    can_back_to_back <= '1';
                else
                    can_back_to_back <= '0';
                end if;
                save_row <= addr_row;
                save_bank <= addr_bank;
                save_col <= addr_col;
                save_wr <= write_sig;
                save_data_in <= data_in;
                save_byte_enable <= byte_sel;
                save_burst_len <= burst_len;
                ready_for_new <= '0';
                if write_sig = '1' then
                    R_ready_out(R_next_port) <= '1';
                else
                    read_done <= false;
                end if;
            end if;

            case state is
            when s_startup =>
                iob_CKE <= '1';
                if startup_refresh_count = startup_refresh_max-31 then
                    iob_command <= CMD_PRECHARGE;
                    iob_address(prefresh_cmd) <= '1';
                    iob_bank <= (others => '0');
                elsif startup_refresh_count = startup_refresh_max-23 then
                    iob_command <= CMD_REFRESH;
                elsif startup_refresh_count = startup_refresh_max-15 then
                    iob_command <= CMD_REFRESH;
                elsif startup_refresh_count = startup_refresh_max-7 then
                    iob_command <= CMD_LOAD_MODE_REG;
                    if C_cas = 2 then
                        iob_address <= MODE_REG_CAS_2;
                    else
                        iob_address <= MODE_REG_CAS_3;
                    end if;
                end if;
                if startup_refresh_count = 0 then
                    state <= s_idle;
                    ready_for_new <= '1';
                    read_done <= true;
                    startup_refresh_count <= to_unsigned(2048 - cycles_per_refresh+1,14);
                end if;

            when s_idle_in_6 => state <= s_idle_in_5;
            when s_idle_in_5 => state <= s_idle_in_4;
            when s_idle_in_4 => state <= s_idle_in_3;
            when s_idle_in_3 => state <= s_idle_in_2;
            when s_idle_in_2 => state <= s_idle_in_1;
            when s_idle_in_1 => state <= s_idle;

            when s_idle =>
                if pending_refresh = '1' or forcing_refresh = '1' then
                    state <= s_idle_in_6;
                    iob_command <= CMD_REFRESH;
                    startup_refresh_count <= startup_refresh_count - cycles_per_refresh+1;
                elsif ready_for_new = '0' then
                    if C_ras = 2 then
                        state <= s_open_in_1;
                    else
                        state <= s_open_in_2;
                    end if;
                    iob_command <= CMD_ACTIVE;
                    iob_address <= save_row;
                    iob_bank <= save_bank;
                end if;

            when s_open_in_2 => state <= s_open_in_1;

            when s_open_in_1 =>
                if save_wr = '1' then
                    state <= s_write_1;
                    iob_dq_hiz <= '0';
                    iob_data <= save_data_in(15 downto 0);
                else
                    iob_dq_hiz <= '1';
                    state <= s_read_1;
                end if;
                ready_for_new <= '1';

            when s_read_1 =>
                state <= s_read_2;
                iob_command <= CMD_READ;
                iob_address <= save_col;
                iob_bank <= save_bank;
                iob_address(prefresh_cmd) <= '0';
                data_ready_delay(data_ready_delay'high) <= '1';
                iob_dqm <= (others => '0');
                dqm_sr(1 downto 0) <= (others => '0');

            when s_read_2 =>
                if unsigned(save_burst_len) /= 0 then
                    state <= s_read_1;
                    save_burst_len <= std_logic_vector(unsigned(save_burst_len) - 1);
                    save_col <= std_logic_vector(unsigned(save_col) + 2);
                else
                    state <= s_read_3;
                end if;
                if C_cas = 3 then
                    dqm_sr(1 downto 0) <= (others => '0');
                end if;

            when s_read_3 =>
                if C_cas = 2 then
                    state <= s_precharge;
                else
                    state <= s_read_4;
                end if;

            when s_read_4 =>
                state <= s_precharge;

            when s_write_1 =>
                state <= s_write_2;
                iob_command <= CMD_WRITE;
                iob_address <= save_col;
                iob_address(prefresh_cmd) <= '0';
                iob_bank <= save_bank;
                iob_dqm <= NOT save_byte_enable(1 downto 0);
                dqm_sr(1 downto 0) <= NOT save_byte_enable(3 downto 2);
                iob_data <= save_data_in(15 downto 0);
                iob_data_next <= save_data_in(31 downto 16);

            when s_write_2 =>
                state <= s_write_3;
                iob_data <= iob_data_next;
                if forcing_refresh = '0' and ready_for_new = '0' and can_back_to_back = '1' then
                    if save_wr = '1' then
                        state <= s_write_1;
                        ready_for_new <= '1';
                    end if;
                end if;

            when s_write_3 =>
                if forcing_refresh = '0' and ready_for_new = '0' and can_back_to_back = '1' then
                    if save_wr = '1' then
                        state <= s_write_1;
                        ready_for_new <= '1';
                    else
                        state <= s_read_1;
                        iob_dq_hiz <= '1';
                        ready_for_new <= '1';
                    end if;
                else
                    iob_dq_hiz <= '1';
                    state <= s_precharge;
                end if;

            when s_precharge =>
                if C_pre = 2 then
                    state <= s_idle_in_2;
                else
                    state <= s_idle_in_3;
                end if;
                iob_command <= CMD_PRECHARGE;
                iob_address(prefresh_cmd) <= '1';

            when others =>
                state <= s_startup;
                ready_for_new <= '0';
                startup_refresh_count <= startup_refresh_max-to_unsigned(sdram_startup_cycles,14);
            end case;

            if reset = '1' then
                state <= s_startup;
                ready_for_new <= '0';
                startup_refresh_count <= startup_refresh_max-to_unsigned(sdram_startup_cycles,14);
            end if;
        end if;
    end process;
end Behavioral;
