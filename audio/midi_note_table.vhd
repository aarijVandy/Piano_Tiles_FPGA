-- =============================================================================
-- MIDI Note to Phase Step Lookup Table
--
-- Maps MIDI note numbers (0-127) to DDS phase accumulator step values.
-- Formula: step = round(440 * 2^((note-69)/12) * 65536 / 48000)
--
-- With a 16-bit phase accumulator and 48 kHz sample rate:
--   Actual frequency = step * 48000 / 65536
--
-- Reference:
--   Note 21 (A0) :   27.50 Hz  step=38
--   Note 60 (C4) :  261.63 Hz  step=357
--   Note 69 (A4) :  440.00 Hz  step=601
--   Note 84 (C6) : 1046.50 Hz  step=1429
--   Note 108 (C8): 4186.01 Hz  step=5715
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity midi_note_table is
    port (
        clk       : in  std_logic;
        note_num  : in  std_logic_vector(6 downto 0);   -- 0 to 127
        phase_step: out std_logic_vector(15 downto 0)    -- DDS phase increment
    );
end entity midi_note_table;

architecture rtl of midi_note_table is

    type rom_type is array (0 to 127) of integer range 0 to 65535;
    constant NOTE_TABLE : rom_type := (
           11,    12,    13,    13,    14,    15,    16,    17,
           18,    19,    20,    21,    22,    24,    25,    27,
           28,    30,    32,    33,    35,    38,    40,    42,
           45,    47,    50,    53,    56,    60,    63,    67,
           71,    75,    80,    84,    89,    95,   100,   106,
          113,   119,   126,   134,   142,   150,   159,   169,
          179,   189,   200,   212,   225,   238,   253,   268,
          284,   300,   318,   337,   357,   378,   401,   425,
          450,   477,   505,   535,   567,   601,   636,   674,
          714,   757,   802,   850,   900,   954,  1010,  1070,
         1134,  1201,  1273,  1349,  1429,  1514,  1604,  1699,
         1800,  1907,  2021,  2141,  2268,  2403,  2546,  2697,
         2858,  3028,  3208,  3398,  3600,  3815,  4041,  4282,
         4536,  4806,  5092,  5395,  5715,  6055,  6415,  6797,
         7201,  7629,  8083,  8563,  9072,  9612, 10184, 10789,
        11431, 12110, 12830, 13593, 14402, 15258, 16165, 17127
    );

begin

    process(clk)
    begin
        if rising_edge(clk) then
            phase_step <= std_logic_vector(to_unsigned(
                NOTE_TABLE(to_integer(unsigned(note_num))), 16));
        end if;
    end process;

end architecture rtl;
