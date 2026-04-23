-- wav_player.vhd
--
-- Streams the song out of SDRAM at WAV_SAMPLE_RATE_HZ, holding each
-- sample for UPSAMPLE_RATIO I2S frames so the ~48.83 kHz DAC rate
-- effectively plays 8 kHz source audio.
--
-- Enable semantics:
--   enable='1' plays forward; wraps back to sample 0 at end of song.
--   A '1'->'0' transition stops playback and resets the read pointer to
--   sample 0 so the next enable pulse starts the song from the beginning.
--
-- While disabled, the player outputs silence (0x0000).
--
-- The SDRAM read is pre-issued right after the I2S sample_req pulse, so
-- the data is back well before the next frame needs it (SDRAM read
-- latency at 50 MHz is ~15 cycles, while a frame is 1024 cycles).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.audio_pkg.all;

entity wav_player is
    generic (
        SDRAM_ADDR_BITS : integer := 25
    );
    port (
        clk_50        : in  std_logic;
        reset         : in  std_logic;

        enable        : in  std_logic;       -- game PLAYING gate
        loader_done   : in  std_logic;       -- wait for SDRAM fill
        sample_req    : in  std_logic;       -- 1-cycle pulse per I2S frame

        -- SDRAM command port
        sdram_cmd_valid : out std_logic;
        sdram_cmd_wr    : out std_logic;
        sdram_cmd_addr  : out std_logic_vector(SDRAM_ADDR_BITS-1 downto 0);
        sdram_cmd_wdata : out std_logic_vector(15 downto 0);
        sdram_cmd_ready : in  std_logic;
        sdram_rd_data   : in  std_logic_vector(15 downto 0);
        sdram_rd_valid  : in  std_logic;

        -- Output to I2S TX
        sample_out    : out std_logic_vector(15 downto 0)
    );
end wav_player;

architecture rtl of wav_player is

    type state_t is (S_IDLE, S_ISSUE, S_WAIT_DATA);
    signal state : state_t := S_IDLE;

    signal enable_d    : std_logic := '0';
    signal idx         : unsigned(16 downto 0) := (others => '0');
    signal upsample_cnt: integer range 0 to UPSAMPLE_RATIO-1 := 0;

    signal sample_latch: std_logic_vector(15 downto 0) := (others => '0');
    signal fetch_request : std_logic := '0';

    signal sdram_valid_r : std_logic := '0';
    signal sdram_addr_r  : std_logic_vector(SDRAM_ADDR_BITS-1 downto 0) := (others => '0');

    signal sample_out_r  : std_logic_vector(15 downto 0) := (others => '0');

begin

    sdram_cmd_valid <= sdram_valid_r;
    sdram_cmd_wr    <= '0';  -- read only
    sdram_cmd_addr  <= sdram_addr_r;
    sdram_cmd_wdata <= (others => '0');

    sample_out <= sample_out_r;

    process (clk_50)
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                enable_d      <= '0';
                idx           <= (others => '0');
                upsample_cnt  <= 0;
                sample_latch  <= (others => '0');
                sample_out_r  <= (others => '0');
                fetch_request <= '0';
                sdram_valid_r <= '0';
                state         <= S_IDLE;
            else

                sdram_valid_r <= '0';  -- default, pulse below
                enable_d      <= enable;

                -- Falling edge of enable: stop & rewind.
                if enable_d = '1' and enable = '0' then
                    idx          <= (others => '0');
                    upsample_cnt <= 0;
                    sample_latch <= (others => '0');
                    fetch_request<= '0';
                    state        <= S_IDLE;
                end if;

                -- Advance on each I2S frame while enabled and loaded.
                if enable = '1' and loader_done = '1' and sample_req = '1' then
                    if upsample_cnt = UPSAMPLE_RATIO-1 then
                        upsample_cnt <= 0;
                        -- advance sample pointer, wrap at end of song
                        if idx = to_unsigned(WAV_SAMPLE_COUNT-1, idx'length) then
                            idx <= (others => '0');
                        else
                            idx <= idx + 1;
                        end if;
                        fetch_request <= '1';  -- request a new SDRAM read
                    else
                        upsample_cnt <= upsample_cnt + 1;
                    end if;
                end if;

                -- Current output: previously-latched sample (or 0 when off)
                if enable = '1' and loader_done = '1' then
                    sample_out_r <= sample_latch;
                else
                    sample_out_r <= (others => '0');
                end if;

                -- SDRAM fetch FSM
                case state is
                    when S_IDLE =>
                        if fetch_request = '1' then
                            sdram_addr_r  <= std_logic_vector(resize(idx, SDRAM_ADDR_BITS));
                            sdram_valid_r <= '1';
                            state         <= S_ISSUE;
                        end if;

                    when S_ISSUE =>
                        sdram_valid_r <= '1';
                        if sdram_cmd_ready = '1' then
                            sdram_valid_r <= '0';
                            fetch_request <= '0';
                            state         <= S_WAIT_DATA;
                        end if;

                    when S_WAIT_DATA =>
                        if sdram_rd_valid = '1' then
                            sample_latch <= sdram_rd_data;
                            state        <= S_IDLE;
                        end if;

                end case;

            end if;
        end if;
    end process;

end rtl;
