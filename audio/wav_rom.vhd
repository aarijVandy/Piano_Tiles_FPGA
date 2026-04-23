-- wav_rom.vhd
--
-- On-chip ROM holding the 16-bit signed mono 8 kHz WAV samples. Generated
-- by wav_to_mif.py; drop the produced song.mif next to this file so the
-- RAM initializer attribute picks it up at synthesis time.
--
-- Why ROM -> SDRAM -> DAC instead of ROM -> DAC directly?
--   - The SDRAM requirement comes from the game's broader memory plan,
--     and building this path lets future work (longer songs, multiple
--     tracks) scale without redesigning.
--   - We can't preload external SDRAM from the .sof bitstream, so a small
--     block-RAM shadow of the song is the bootstrap source.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.audio_pkg.all;

entity wav_rom is
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(16 downto 0);   -- up to 128 K samples
        data  : out std_logic_vector(15 downto 0)
    );
end wav_rom;

architecture rtl of wav_rom is

    constant DEPTH : integer := 131072;  -- 2^17 = 128K words

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(15 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- Tell Quartus to preload this block RAM from the generated MIF.
    attribute ram_init_file : string;
    attribute ram_init_file of mem : signal is "audio/song.mif";

    -- Hint: this should live in block RAM, not registers.
    attribute ramstyle : string;
    attribute ramstyle of mem : signal is "M9K";

    signal data_r : std_logic_vector(15 downto 0) := (others => '0');

begin

    process (clk)
    begin
        if rising_edge(clk) then
            data_r <= mem(to_integer(unsigned(addr)));
        end if;
    end process;

    data <= data_r;

end rtl;
