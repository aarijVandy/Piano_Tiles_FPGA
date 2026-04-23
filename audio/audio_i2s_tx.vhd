-- audio_i2s_tx.vhd
--
-- Single-clock (50 MHz) I2S transmitter for the WM8731. Instead of running
-- on a 12.288 MHz PLL output, it derives all audio clocks from CLOCK_50 by
-- division so no PLL generation is required.
--
-- Clock tree:
--   CLOCK_50  50.000 MHz  --> /4   --> MCLK (AUD_XCK) 12.500 MHz
--                              /4   --> BCLK          3.125 MHz
--                              /256 --> DACLRCK       ~48.828 kHz (fs)
--
-- The 1.7% fs shift vs. the nominal 48 kHz is inaudible for a game demo;
-- the codec's interpolation filters simply run slightly fast.
--
-- Frame layout (1024 CLOCK_50 cycles = 256 MCLK = 64 BCLK = 1 fs period):
--   frame_cnt(1) -> MCLK
--   frame_cnt(3) -> BCLK
--   frame_cnt(9) -> DACLRCK        ('0' = Left half, '1' = Right half)
--
-- I2S timing: data begins one BCLK cycle AFTER each LRCK transition, MSB
-- first. With 32 BCLK cycles per half-frame and 16-bit samples, BCLK slots
-- 1..16 carry data; slot 0 and 17..31 are silent.
--
-- sample_req pulses for one CLOCK_50 cycle late in each frame so upstream
-- logic has time to present the next left/right word before it's shifted.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_i2s_tx is
    port (
        clk_50       : in  std_logic;
        reset        : in  std_logic;

        -- Sample inputs (signed 16-bit, mono can tie L=R)
        left_data    : in  std_logic_vector(15 downto 0);
        right_data   : in  std_logic_vector(15 downto 0);

        -- Audio codec pins
        aud_xck      : out std_logic;   -- MCLK 12.5 MHz
        aud_bclk     : out std_logic;   -- BCLK 3.125 MHz
        aud_daclrck  : out std_logic;   -- LRCK ~48.8 kHz
        aud_dacdat   : out std_logic;

        -- Upstream notification: one cycle pulse per audio frame
        sample_req   : out std_logic
    );
end audio_i2s_tx;

architecture rtl of audio_i2s_tx is

    signal frame_cnt   : unsigned(9 downto 0) := (others => '0');

    signal left_latch  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_latch : std_logic_vector(15 downto 0) := (others => '0');

    signal dacdat_r    : std_logic := '0';
    signal sample_req_r: std_logic := '0';

    -- Pulse sample_req a few cycles before frame wraps so upstream has
    -- time to present new data before the next frame begins shifting.
    constant REQ_PHASE : unsigned(9 downto 0) := to_unsigned(1020, 10);

begin

    aud_xck     <= frame_cnt(1);
    aud_bclk    <= frame_cnt(3);
    aud_daclrck <= frame_cnt(9);
    aud_dacdat  <= dacdat_r;
    sample_req  <= sample_req_r;

    process (clk_50)
        variable half_pos : unsigned(4 downto 0);  -- 0..31 BCLK slot within half-frame
        variable bit_sel  : integer range 0 to 15;
        variable is_data  : boolean;
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                frame_cnt    <= (others => '0');
                left_latch   <= (others => '0');
                right_latch  <= (others => '0');
                dacdat_r     <= '0';
                sample_req_r <= '0';
            else
                frame_cnt <= frame_cnt + 1;

                -- Latch new samples at frame start to keep them stable for
                -- the whole frame.
                if frame_cnt = 0 then
                    left_latch  <= left_data;
                    right_latch <= right_data;
                end if;

                -- Pulse sample_req a handful of cycles before frame wrap
                if frame_cnt = REQ_PHASE then
                    sample_req_r <= '1';
                else
                    sample_req_r <= '0';
                end if;

                -- Compute current position within the current half-frame
                -- frame_cnt(8..4) gives BCLK count 0..31 within half-frame
                half_pos := frame_cnt(8 downto 4);

                if half_pos >= 1 and half_pos <= 16 then
                    bit_sel := 16 - to_integer(half_pos);  -- 1->15, 16->0
                    is_data := true;
                else
                    bit_sel := 0;
                    is_data := false;
                end if;

                if is_data then
                    if frame_cnt(9) = '0' then
                        dacdat_r <= left_latch(bit_sel);
                    else
                        dacdat_r <= right_latch(bit_sel);
                    end if;
                else
                    dacdat_r <= '0';
                end if;

            end if;
        end if;
    end process;

end rtl;
