-- wav_loader.vhd
--
-- One-shot copy of the song ROM into SDRAM at power-up. Runs once right
-- after the SDRAM controller finishes its init sequence. Simple two-state
-- machine that reads word N from the ROM, writes it to SDRAM address N,
-- increments until WAV_SAMPLE_COUNT, then holds done='1' forever.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.audio_pkg.all;

entity wav_loader is
    generic (
        SDRAM_ADDR_BITS : integer := 25
    );
    port (
        clk_50        : in  std_logic;
        reset         : in  std_logic;

        init_done     : in  std_logic;  -- from SDRAM controller

        -- ROM read port
        rom_addr      : out std_logic_vector(16 downto 0);
        rom_data      : in  std_logic_vector(15 downto 0);

        -- SDRAM command port (shared, arbitrated in audio_top)
        sdram_cmd_valid : out std_logic;
        sdram_cmd_wr    : out std_logic;
        sdram_cmd_addr  : out std_logic_vector(SDRAM_ADDR_BITS-1 downto 0);
        sdram_cmd_wdata : out std_logic_vector(15 downto 0);
        sdram_cmd_ready : in  std_logic;

        done          : out std_logic
    );
end wav_loader;

architecture rtl of wav_loader is

    type state_t is (S_IDLE, S_FETCH, S_WAIT_ROM, S_ISSUE, S_AWAIT_ACK, S_DONE);
    signal state : state_t := S_IDLE;

    signal idx      : unsigned(16 downto 0) := (others => '0');
    signal rom_addr_r : std_logic_vector(16 downto 0) := (others => '0');
    signal sdram_valid_r : std_logic := '0';
    signal sdram_wdata_r : std_logic_vector(15 downto 0) := (others => '0');
    signal done_r   : std_logic := '0';

begin

    rom_addr        <= rom_addr_r;
    sdram_cmd_valid <= sdram_valid_r;
    sdram_cmd_wr    <= '1';   -- always writes
    sdram_cmd_addr  <= std_logic_vector(resize(idx, sdram_cmd_addr'length));
    sdram_cmd_wdata <= sdram_wdata_r;
    done            <= done_r;

    process (clk_50)
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                state          <= S_IDLE;
                idx            <= (others => '0');
                rom_addr_r     <= (others => '0');
                sdram_valid_r  <= '0';
                sdram_wdata_r  <= (others => '0');
                done_r         <= '0';
            else
                sdram_valid_r <= '0';  -- default

                case state is

                    when S_IDLE =>
                        if init_done = '1' then
                            rom_addr_r <= std_logic_vector(idx);
                            state      <= S_WAIT_ROM;
                        end if;

                    when S_FETCH =>
                        rom_addr_r <= std_logic_vector(idx);
                        state      <= S_WAIT_ROM;

                    when S_WAIT_ROM =>
                        -- ROM has 1-cycle read latency; data valid next clock.
                        sdram_wdata_r <= rom_data;
                        state         <= S_ISSUE;

                    when S_ISSUE =>
                        sdram_valid_r <= '1';
                        if sdram_cmd_ready = '1' then
                            -- Controller accepted this cycle
                            sdram_valid_r <= '0';
                            if idx = to_unsigned(WAV_SAMPLE_COUNT-1, idx'length) then
                                state  <= S_DONE;
                                done_r <= '1';
                            else
                                idx   <= idx + 1;
                                state <= S_AWAIT_ACK;
                            end if;
                        end if;

                    when S_AWAIT_ACK =>
                        -- Give controller a beat to return to IDLE before
                        -- fetching the next sample.
                        state <= S_FETCH;

                    when S_DONE =>
                        done_r <= '1';

                end case;
            end if;
        end if;
    end process;

end rtl;
