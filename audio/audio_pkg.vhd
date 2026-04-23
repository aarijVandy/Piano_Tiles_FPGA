-- audio_pkg.vhd
-- Shared constants for the audio pipeline.
library ieee;
use ieee.std_logic_1164.all;

package audio_pkg is

    -- WAV source format (what wav_to_mif.py produces)
    constant WAV_SAMPLE_RATE_HZ : integer := 8000;   -- mono 8 kHz
    constant WAV_SAMPLE_BITS    : integer := 16;     -- signed

    -- Total number of samples stored in the song ROM / SDRAM.
    -- wav_to_mif.py reports this value; update it whenever the song changes.
    constant WAV_SAMPLE_COUNT   : integer := 120000; -- 15 s at 8 kHz

    -- SDRAM address width (bank 0, single bank suffices for <= 8M samples)
    -- 23 bits covers up to 8M samples in one bank (row 13 + col 10)
    constant SDRAM_ADDR_BITS    : integer := 23;

    -- DAC sample rate: MCLK (12.5 MHz) / 256 ~= 48.828 kHz
    -- Playback upsampling ratio: DAC_fs / WAV_fs ~= 48828/8000 ~= 6.
    constant UPSAMPLE_RATIO     : integer := 6;

end package;

package body audio_pkg is
end package body;
