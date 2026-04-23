-- audio_top.vhd
--
-- Stitches the audio pipeline together and exposes a single, easy
-- interface to the FPGA top-level: give it clock/reset + the game's
-- `playing` signal and wire up the DE2-115 DRAM / audio codec pins.
--
--   ROM --(loader)--> SDRAM --(player)--> I2S TX --> WM8731 --> speaker
--                                  ^
--                                  |
--                             playing gate
--
-- SDRAM arbitration: trivial priority. While the loader is active it
-- owns the controller command port; once loader_done goes high the
-- player is granted all future cycles.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.audio_pkg.all;

entity audio_top is
    port (
        clk_50       : in    std_logic;
        reset        : in    std_logic;

        -- Game signal: '1' while in PLAYING state, '0' otherwise.
        playing      : in    std_logic;

        -- WM8731 audio codec
        aud_xck      : out   std_logic;
        aud_bclk     : out   std_logic;
        aud_daclrck  : out   std_logic;
        aud_dacdat   : out   std_logic;
        i2c_sclk     : out   std_logic;
        i2c_sdat     : inout std_logic;

        -- SDRAM pins (DE2-115 chip 0 half is used; chip 1 held off)
        dram_clk     : out   std_logic;
        dram_cke     : out   std_logic;
        dram_cs_n    : out   std_logic;
        dram_ras_n   : out   std_logic;
        dram_cas_n   : out   std_logic;
        dram_we_n    : out   std_logic;
        dram_ba      : out   std_logic_vector(1 downto 0);
        dram_addr    : out   std_logic_vector(12 downto 0);
        dram_dqm     : out   std_logic_vector(3 downto 0);
        dram_dq      : inout std_logic_vector(31 downto 0)
    );
end audio_top;

architecture rtl of audio_top is

    constant AB : integer := 25;  -- SDRAM address bits

    -- I2C
    signal i2c_done : std_logic;

    -- SDRAM controller
    signal sdram_cmd_valid : std_logic;
    signal sdram_cmd_wr    : std_logic;
    signal sdram_cmd_addr  : std_logic_vector(AB-1 downto 0);
    signal sdram_cmd_wdata : std_logic_vector(15 downto 0);
    signal sdram_cmd_ready : std_logic;
    signal sdram_rd_data   : std_logic_vector(15 downto 0);
    signal sdram_rd_valid  : std_logic;
    signal sdram_init_done : std_logic;

    -- Loader
    signal ld_rom_addr      : std_logic_vector(16 downto 0);
    signal ld_cmd_valid     : std_logic;
    signal ld_cmd_wr        : std_logic;
    signal ld_cmd_addr      : std_logic_vector(AB-1 downto 0);
    signal ld_cmd_wdata     : std_logic_vector(15 downto 0);
    signal loader_done      : std_logic;

    -- Player
    signal pl_cmd_valid     : std_logic;
    signal pl_cmd_wr        : std_logic;
    signal pl_cmd_addr      : std_logic_vector(AB-1 downto 0);
    signal pl_cmd_wdata     : std_logic_vector(15 downto 0);
    signal sample_out       : std_logic_vector(15 downto 0);

    -- ROM
    signal rom_data         : std_logic_vector(15 downto 0);

    -- I2S
    signal sample_req       : std_logic;

    -- Master "audio ready" gate: wait for I2C + SDRAM init before running
    -- any audio-facing state machines. Prevents garbage on first frames.
    signal audio_reset : std_logic;

begin

    audio_reset <= reset or (not i2c_done) or (not sdram_init_done);

    -- ------ I2C startup config for the WM8731 ------
    i2c_cfg : entity work.audio_i2c_config
        port map (
            clk_50   => clk_50,
            reset    => reset,
            i2c_sclk => i2c_sclk,
            i2c_sdat => i2c_sdat,
            done     => i2c_done
        );

    -- ------ SDRAM controller ------
    sdram_ctl : entity work.sdram_controller
        generic map (ADDR_BITS => AB)
        port map (
            clk_50     => clk_50,
            reset      => reset,

            cmd_valid  => sdram_cmd_valid,
            cmd_wr     => sdram_cmd_wr,
            cmd_addr   => sdram_cmd_addr,
            cmd_wdata  => sdram_cmd_wdata,
            cmd_ready  => sdram_cmd_ready,
            rd_data    => sdram_rd_data,
            rd_valid   => sdram_rd_valid,
            init_done  => sdram_init_done,

            dram_clk   => dram_clk,
            dram_cke   => dram_cke,
            dram_cs_n  => dram_cs_n,
            dram_ras_n => dram_ras_n,
            dram_cas_n => dram_cas_n,
            dram_we_n  => dram_we_n,
            dram_ba    => dram_ba,
            dram_addr  => dram_addr,
            dram_dqm   => dram_dqm,
            dram_dq    => dram_dq
        );

    -- ------ On-chip WAV sample ROM ------
    rom : entity work.wav_rom
        port map (
            clk  => clk_50,
            addr => ld_rom_addr,
            data => rom_data
        );

    -- ------ ROM -> SDRAM one-shot loader ------
    loader : entity work.wav_loader
        generic map (SDRAM_ADDR_BITS => AB)
        port map (
            clk_50          => clk_50,
            reset           => reset,
            init_done       => sdram_init_done,
            rom_addr        => ld_rom_addr,
            rom_data        => rom_data,
            sdram_cmd_valid => ld_cmd_valid,
            sdram_cmd_wr    => ld_cmd_wr,
            sdram_cmd_addr  => ld_cmd_addr,
            sdram_cmd_wdata => ld_cmd_wdata,
            sdram_cmd_ready => sdram_cmd_ready,
            done            => loader_done
        );

    -- ------ SDRAM -> DAC playback ------
    player : entity work.wav_player
        generic map (SDRAM_ADDR_BITS => AB)
        port map (
            clk_50          => clk_50,
            reset           => audio_reset,
            enable          => playing,
            loader_done     => loader_done,
            sample_req      => sample_req,
            sdram_cmd_valid => pl_cmd_valid,
            sdram_cmd_wr    => pl_cmd_wr,
            sdram_cmd_addr  => pl_cmd_addr,
            sdram_cmd_wdata => pl_cmd_wdata,
            sdram_cmd_ready => sdram_cmd_ready,
            sdram_rd_data   => sdram_rd_data,
            sdram_rd_valid  => sdram_rd_valid,
            sample_out      => sample_out
        );

    -- ------ Command-port arbiter (loader owns until done, then player) ------
    sdram_cmd_valid <= ld_cmd_valid when loader_done = '0' else pl_cmd_valid;
    sdram_cmd_wr    <= ld_cmd_wr    when loader_done = '0' else pl_cmd_wr;
    sdram_cmd_addr  <= ld_cmd_addr  when loader_done = '0' else pl_cmd_addr;
    sdram_cmd_wdata <= ld_cmd_wdata when loader_done = '0' else pl_cmd_wdata;

    -- ------ I2S transmitter (generates MCLK/BCLK/LRCK and shifts DACDAT) ------
    i2s_tx : entity work.audio_i2s_tx
        port map (
            clk_50      => clk_50,
            reset       => reset,
            left_data   => sample_out,
            right_data  => sample_out,     -- mono: drive both channels
            aud_xck     => aud_xck,
            aud_bclk    => aud_bclk,
            aud_daclrck => aud_daclrck,
            aud_dacdat  => aud_dacdat,
            sample_req  => sample_req
        );

end rtl;
