-- sdram_controller.vhd
--
-- Minimal SDRAM controller for the DE2-115's ISSI 8M x 16 x 4-bank chips
-- (IS42S16320 family). Only implements the commands the audio pipeline
-- needs: init, single-word READ with auto-precharge, single-word WRITE
-- with auto-precharge, and periodic AUTO REFRESH.
--
-- Clocking:
--   Runs on CLOCK_50. DRAM_CLK is driven as (not clk_50) so the chip
--   samples address / data one half-cycle after the FPGA registers them,
--   giving ~10 ns of setup slack at 50 MHz. Good enough at this rate;
--   swap in a PLL with a phase-shifted output if you ever push past
--   ~80 MHz.
--
-- Timings assumed (-7 grade, datasheet minimums at 50 MHz = 20 ns period):
--   tRP  >= 15 ns -> 2 cycles
--   tRCD >= 15 ns -> 2 cycles
--   tRC  >= 60 ns -> 4 cycles
--   tRFC >= 66 ns -> 4 cycles
--   tMRD  = 2 CK  -> 2 cycles
--   CAS latency = 2
--
-- Address packing (25 bits):
--   addr[24:23] = bank
--   addr[22:10] = row (13 bits)
--   addr[9:0]   = col (10 bits)
--
-- The command interface is single-issue: assert cmd_valid when ready='1',
-- the controller latches it, and pulses rd_valid later for reads. Writes
-- signal completion by simply returning ready='1'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller is
    generic (
        ADDR_BITS : integer := 25
    );
    port (
        clk_50      : in    std_logic;
        reset       : in    std_logic;

        -- Command interface (single-word, auto-precharge)
        cmd_valid   : in    std_logic;
        cmd_wr      : in    std_logic;                       -- 1=write, 0=read
        cmd_addr    : in    std_logic_vector(ADDR_BITS-1 downto 0);
        cmd_wdata   : in    std_logic_vector(15 downto 0);
        cmd_ready   : out   std_logic;

        rd_data     : out   std_logic_vector(15 downto 0);
        rd_valid    : out   std_logic;

        init_done   : out   std_logic;

        -- SDRAM pins (DE2-115 names)
        dram_clk    : out   std_logic;
        dram_cke    : out   std_logic;
        dram_cs_n   : out   std_logic;
        dram_ras_n  : out   std_logic;
        dram_cas_n  : out   std_logic;
        dram_we_n   : out   std_logic;
        dram_ba     : out   std_logic_vector(1 downto 0);
        dram_addr   : out   std_logic_vector(12 downto 0);
        dram_dqm    : out   std_logic_vector(3 downto 0);
        dram_dq     : inout std_logic_vector(31 downto 0)
    );
end sdram_controller;

architecture rtl of sdram_controller is

    -- ----- Command encoding: CS,RAS,CAS,WE -----
    constant CMD_NOP      : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE   : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ     : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE    : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHARGE: std_logic_vector(3 downto 0) := "0010";
    constant CMD_REFRESH  : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOADMODE : std_logic_vector(3 downto 0) := "0000";
    constant CMD_DESELECT : std_logic_vector(3 downto 0) := "1111";

    -- Mode register: CL=2, BL=1, sequential, standard, write single
    -- A[12:0] = 000_0_00_010_0_000 = 0x020 (plain mode) or 0x220 (single writes)
    -- We use write-single to pair with BL=1: A9=1
    constant MODE_WORD : std_logic_vector(12 downto 0) := "0001000100000";
    --                                                     ^A12-A9 A6-A4 A3 A2-A0
    -- A9=1 (single write), A6-A4=010 (CL=2), A3=0 (seq), A2-A0=000 (BL=1)

    -- ----- Timing constants (in 50 MHz cycles) -----
    constant T_POWERUP : integer := 10_100;  -- >= 200 us
    constant T_RP      : integer := 2;
    constant T_RFC     : integer := 7;
    constant T_MRD     : integer := 3;
    constant T_RCD     : integer := 2;
    constant T_RC      : integer := 4;       -- row cycle
    constant CAS_LAT   : integer := 2;

    -- Refresh every ~7.5 us to stay ahead of the 7.8 us max per row.
    constant T_REFRESH_INTERVAL : integer := 370;

    type state_t is (
        S_POWERUP, S_INIT_PRECHARGE, S_INIT_PRE_WAIT,
        S_INIT_REFRESH1, S_INIT_REF1_WAIT,
        S_INIT_REFRESH2, S_INIT_REF2_WAIT,
        S_INIT_LOADMODE, S_INIT_MRD_WAIT,
        S_IDLE,
        S_ACT, S_ACT_WAIT,
        S_RW,
        S_READ_WAIT,
        S_WRITE_CLEANUP,
        S_AUTO_REFRESH, S_REFRESH_WAIT
    );

    signal state : state_t := S_POWERUP;

    signal timer : integer range 0 to T_POWERUP := 0;

    signal refresh_cnt : integer range 0 to T_REFRESH_INTERVAL := 0;
    signal refresh_due : std_logic := '0';

    signal cmd_q      : std_logic_vector(3 downto 0) := CMD_NOP;
    signal addr_q     : std_logic_vector(12 downto 0) := (others => '0');
    signal ba_q       : std_logic_vector(1 downto 0) := (others => '0');
    signal dqm_q      : std_logic_vector(3 downto 0) := (others => '1');
    signal dq_out_q   : std_logic_vector(15 downto 0) := (others => '0');
    signal dq_drive_q : std_logic := '0';
    signal cke_q      : std_logic := '0';

    -- Latched request
    signal req_wr    : std_logic := '0';
    signal req_bank  : std_logic_vector(1 downto 0) := "00";
    signal req_row   : std_logic_vector(12 downto 0) := (others => '0');
    signal req_col   : std_logic_vector(9 downto 0)  := (others => '0');
    signal req_wdata : std_logic_vector(15 downto 0) := (others => '0');

    signal rd_data_r : std_logic_vector(15 downto 0) := (others => '0');
    signal rd_valid_r: std_logic := '0';
    signal cmd_ready_r : std_logic := '0';

begin

    dram_clk  <= not clk_50;   -- 180 degree phase; OK at 50 MHz
    dram_cke  <= cke_q;
    dram_cs_n <= cmd_q(3);
    dram_ras_n<= cmd_q(2);
    dram_cas_n<= cmd_q(1);
    dram_we_n <= cmd_q(0);
    dram_ba   <= ba_q;
    dram_addr <= addr_q;
    dram_dqm  <= dqm_q;

    -- Drive only the low 16 bits (chip 0); leave chip 1 high-Z.
    dram_dq(15 downto 0)  <= dq_out_q when dq_drive_q = '1' else (others => 'Z');
    dram_dq(31 downto 16) <= (others => 'Z');

    rd_data   <= rd_data_r;
    rd_valid  <= rd_valid_r;
    cmd_ready <= cmd_ready_r;
    init_done <= '1' when state /= S_POWERUP and
                          state /= S_INIT_PRECHARGE and
                          state /= S_INIT_PRE_WAIT and
                          state /= S_INIT_REFRESH1 and
                          state /= S_INIT_REF1_WAIT and
                          state /= S_INIT_REFRESH2 and
                          state /= S_INIT_REF2_WAIT and
                          state /= S_INIT_LOADMODE and
                          state /= S_INIT_MRD_WAIT
                 else '0';

    process (clk_50)
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                state        <= S_POWERUP;
                timer        <= T_POWERUP;
                refresh_cnt  <= 0;
                refresh_due  <= '0';
                cmd_q        <= CMD_NOP;
                addr_q       <= (others => '0');
                ba_q         <= (others => '0');
                dqm_q        <= (others => '1');
                dq_out_q     <= (others => '0');
                dq_drive_q   <= '0';
                cke_q        <= '0';
                rd_valid_r   <= '0';
                cmd_ready_r  <= '0';
            else
                -- Default assignments each cycle
                cmd_q       <= CMD_NOP;
                dq_drive_q  <= '0';
                dqm_q       <= "1111";  -- masked by default
                rd_valid_r  <= '0';
                cmd_ready_r <= '0';

                -- Refresh interval timer (free-running once init done)
                if state /= S_POWERUP then
                    if refresh_cnt = T_REFRESH_INTERVAL-1 then
                        refresh_cnt <= 0;
                        refresh_due <= '1';
                    else
                        refresh_cnt <= refresh_cnt + 1;
                    end if;
                end if;

                case state is

                    when S_POWERUP =>
                        cke_q <= '0';
                        if timer = 0 then
                            cke_q <= '1';
                            state <= S_INIT_PRECHARGE;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_INIT_PRECHARGE =>
                        cmd_q   <= CMD_PRECHARGE;
                        addr_q  <= (10 => '1', others => '0'); -- A10=1 all banks
                        timer   <= T_RP;
                        state   <= S_INIT_PRE_WAIT;

                    when S_INIT_PRE_WAIT =>
                        if timer = 0 then
                            state <= S_INIT_REFRESH1;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_INIT_REFRESH1 =>
                        cmd_q <= CMD_REFRESH;
                        timer <= T_RFC;
                        state <= S_INIT_REF1_WAIT;

                    when S_INIT_REF1_WAIT =>
                        if timer = 0 then state <= S_INIT_REFRESH2;
                        else timer <= timer - 1;
                        end if;

                    when S_INIT_REFRESH2 =>
                        cmd_q <= CMD_REFRESH;
                        timer <= T_RFC;
                        state <= S_INIT_REF2_WAIT;

                    when S_INIT_REF2_WAIT =>
                        if timer = 0 then state <= S_INIT_LOADMODE;
                        else timer <= timer - 1;
                        end if;

                    when S_INIT_LOADMODE =>
                        cmd_q  <= CMD_LOADMODE;
                        addr_q <= MODE_WORD;
                        ba_q   <= "00";
                        timer  <= T_MRD;
                        state  <= S_INIT_MRD_WAIT;

                    when S_INIT_MRD_WAIT =>
                        if timer = 0 then
                            state <= S_IDLE;
                            refresh_cnt <= 0;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_IDLE =>
                        if refresh_due = '1' then
                            state       <= S_AUTO_REFRESH;
                            refresh_due <= '0';
                        elsif cmd_valid = '1' then
                            req_wr    <= cmd_wr;
                            req_bank  <= cmd_addr(24 downto 23);
                            req_row   <= cmd_addr(22 downto 10);
                            req_col   <= cmd_addr(9 downto 0);
                            req_wdata <= cmd_wdata;
                            cmd_ready_r <= '1';  -- acknowledge this cycle
                            state <= S_ACT;
                        end if;

                    when S_ACT =>
                        cmd_q  <= CMD_ACTIVE;
                        ba_q   <= req_bank;
                        addr_q <= req_row;
                        timer  <= T_RCD;
                        state  <= S_ACT_WAIT;

                    when S_ACT_WAIT =>
                        if timer = 0 then
                            state <= S_RW;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_RW =>
                        ba_q   <= req_bank;
                        -- A12..A11 = 0, A10 = 1 (auto-precharge), A9..A0 = col
                        addr_q <= "00" & '1' & req_col;
                        dqm_q  <= "1100";  -- enable chip 0 (DQ[15:0]) only

                        if req_wr = '1' then
                            cmd_q      <= CMD_WRITE;
                            dq_out_q   <= req_wdata;
                            dq_drive_q <= '1';
                            state      <= S_WRITE_CLEANUP;
                            timer      <= T_RC - T_RCD;  -- wait the rest of tRC
                        else
                            cmd_q <= CMD_READ;
                            timer <= CAS_LAT;
                            state <= S_READ_WAIT;
                        end if;

                    when S_READ_WAIT =>
                        dqm_q <= "1100";
                        if timer = 0 then
                            -- Data is present on DQ at this rising edge
                            -- (CAS_LAT=2 cycles after the READ command).
                            rd_data_r  <= dram_dq(15 downto 0);
                            rd_valid_r <= '1';
                            state      <= S_IDLE;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_WRITE_CLEANUP =>
                        if timer = 0 then
                            state <= S_IDLE;
                        else
                            timer <= timer - 1;
                        end if;

                    when S_AUTO_REFRESH =>
                        cmd_q <= CMD_REFRESH;
                        timer <= T_RFC;
                        state <= S_REFRESH_WAIT;

                    when S_REFRESH_WAIT =>
                        if timer = 0 then state <= S_IDLE;
                        else timer <= timer - 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
