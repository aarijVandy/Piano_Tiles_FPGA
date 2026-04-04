-- =============================================================================
-- I2S Audio Transmitter for WM8731
-- Generates BCLK, DACLRCK, and DACDAT signals for 16-bit stereo I2S output.
--
-- Clocking:
--   MCLK input = 12.288 MHz (from PLL)
--   BCLK       = MCLK / 4 = 3.072 MHz
--   DACLRCK    = BCLK / 64 = 48 kHz
--
-- Each channel gets 32 BCLK cycles: 1 cycle delay (I2S standard) + 16 data
-- bits (MSB first) + 15 padding zeros.
--
-- Target: DE2-115 (Altera Cyclone IV)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_i2s_tx is
    port (
        mclk        : in  std_logic;   -- 12.288 MHz audio master clock
        reset_n     : in  std_logic;
        left_data   : in  std_logic_vector(15 downto 0);  -- Left channel sample (signed)
        right_data  : in  std_logic_vector(15 downto 0);  -- Right channel sample (signed)
        sample_req  : out std_logic;   -- Pulses high for 1 MCLK when new samples are needed
        aud_bclk    : out std_logic;   -- Bit clock to codec
        aud_daclrck : out std_logic;   -- DAC left/right clock to codec
        aud_dacdat  : out std_logic    -- DAC serial data to codec
    );
end entity audio_i2s_tx;

architecture rtl of audio_i2s_tx is

    -- Master counter: 0 to 255 (256 MCLK cycles per sample frame)
    -- Bit 1:0 = BCLK divider phase (BCLK = counter(1), inverted for proper edge alignment)
    -- Bit 7:2 = BCLK count within frame (0 to 63)
    -- Bit 7   = channel select (0 = left, 1 = right)
    signal mcount    : unsigned(7 downto 0) := (others => '0');

    -- Latched audio data
    signal left_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Shift register for serial output
    signal shift_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Internal signals
    signal bclk_int  : std_logic;
    signal lrck_int  : std_logic;

    -- Derived indices
    signal bclk_count  : unsigned(5 downto 0);  -- 0 to 63
    signal half_count  : unsigned(4 downto 0);   -- position within channel half (0 to 31)

begin

    -- BCLK: divide MCLK by 4. We invert so that data transitions happen
    -- on falling BCLK while MCLK rising edge drives our logic.
    bclk_int   <= not mcount(1);
    bclk_count <= mcount(7 downto 2);
    half_count <= mcount(6 downto 2);

    -- LRCK: low for left channel (bclk_count 0-31), high for right (32-63)
    lrck_int <= mcount(7);

    -- Output assignments
    aud_bclk    <= bclk_int;
    aud_daclrck <= lrck_int;

    -- Serial data output: MSB of shift register during active data bits,
    -- zero during padding and delay slots
    aud_dacdat <= shift_reg(15);

    -- Main process: runs on MCLK rising edge
    process(mclk, reset_n)
    begin
        if reset_n = '0' then
            mcount    <= (others => '0');
            left_reg  <= (others => '0');
            right_reg <= (others => '0');
            shift_reg <= (others => '0');
        elsif rising_edge(mclk) then

            -- Default sample request low
            -- (will be set in the specific cycle below)

            -- Advance master counter
            mcount <= mcount + 1;

            -- Actions at specific points in the frame.
            -- We perform data operations when mcount(1:0) = "11", which is
            -- one MCLK cycle before the falling edge of BCLK. This ensures
            -- data is stable when the codec samples on the BCLK rising edge.

            if mcount(1 downto 0) = "11" then
                case to_integer(half_count) is

                    -- Channel boundary: load shift register
                    when 0 =>
                        if mcount(7) = '0' then
                            -- Beginning of left channel: load left data
                            shift_reg <= left_reg;
                        else
                            -- Beginning of right channel: load right data
                            shift_reg <= right_reg;
                        end if;
                        -- I2S delay slot: shift_reg(15) = MSB, but it will
                        -- be output one BCLK late, which is the I2S standard.
                        -- We actually want to output '0' during the delay slot
                        -- and shift on the next cycle. We'll handle this by
                        -- NOT shifting here.

                    -- Data bits: shift out MSB first (slots 1 through 16)
                    when 1 to 15 =>
                        shift_reg <= shift_reg(14 downto 0) & '0';

                    when 16 =>
                        -- Last data bit was just sent, clear shift register
                        shift_reg <= (others => '0');

                    -- Padding slots 17-31: shift register already zero
                    when others =>
                        null;

                end case;
            end if;

            -- Request new samples near the end of the frame.
            -- This gives the upstream module a full channel period to respond.
            -- We pulse at the start of the right channel's last BCLK cycle.
            if mcount = to_unsigned(252, 8) then
                left_reg  <= left_data;
                right_reg <= right_data;
            end if;

        end if;
    end process;

    -- Sample request: pulse high for one MCLK cycle near end of frame
    sample_req <= '1' when mcount = to_unsigned(252, 8) else '0';

end architecture rtl;
