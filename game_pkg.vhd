-- game_pkg.vhd
-- Shared constants, types, and character codes used across all game modules.
library ieee;
use ieee.std_logic_1164.all;

package game_pkg is

    -- -------------------------------------------------------------------------
    -- Screen dimensions (1024x768 VGA)
    -- -------------------------------------------------------------------------
    constant SCREEN_WIDTH  : integer := 1024;
    constant SCREEN_HEIGHT : integer := 768;

    -- -------------------------------------------------------------------------
    -- Lane geometry
    -- -------------------------------------------------------------------------
    constant LANE_COUNT    : integer := 4;
    constant LANE_WIDTH    : integer := 64; -- Refined from 128. Retains O(1) power-of-two shift optimization while keeping authentic piano key aesthetics. 

    -- -------------------------------------------------------------------------
    -- Note grid dimensions
    -- -------------------------------------------------------------------------
    constant NOTE_VISIBLE  : integer := 6;   -- 768px screen / 6 = 128px per vertical tile (perfect square). Replaces 96.
    constant NOTE_BUFFER   : integer := 1;   -- hidden slide-in row above screen
    constant NOTE_COUNT    : integer := NOTE_VISIBLE + NOTE_BUFFER;
    constant NOTE_HEIGHT   : integer := 16;  -- originally 20. Power of 2 optimizes cascading multiplier tick_counts!

    -- -------------------------------------------------------------------------
    -- Note matrix type: one std_logic_vector per lane
    -- -------------------------------------------------------------------------
    type note_matrix_t is array (0 to LANE_COUNT-1) of std_logic_vector(NOTE_COUNT-1 downto 0);

    -- -------------------------------------------------------------------------
    -- Character array type used for menu / label text strings
    -- Each element is a font_rom character code (integer).
    -- -------------------------------------------------------------------------
    type char_array_t is array (natural range <>) of integer;

    -- -------------------------------------------------------------------------
    -- font_rom character codes
    --   0-9  : digit glyphs  (unchanged)
    --  10-35 : uppercase A-Z
    --  36    : colon ':'
    --  37    : equals '='
    --  63    : SPACE (no glyph -- renders as background)
    -- -------------------------------------------------------------------------
    constant CHAR_SPACE  : integer := 63;

    constant CHAR_A : integer := 10;
    constant CHAR_B : integer := 11;
    constant CHAR_C : integer := 12;
    constant CHAR_D : integer := 13; -- not used; outputs blank
    constant CHAR_E : integer := 14;
    constant CHAR_F : integer := 15; -- not used; outputs blank
    constant CHAR_G : integer := 16;
    constant CHAR_H : integer := 17;
    constant CHAR_I : integer := 18;
    constant CHAR_J : integer := 19; -- not used; outputs blank
    constant CHAR_K : integer := 20;
    constant CHAR_L : integer := 21;
    constant CHAR_M : integer := 22;
    constant CHAR_N : integer := 23;
    constant CHAR_O : integer := 24;
    constant CHAR_P : integer := 25;
    constant CHAR_Q : integer := 26; -- not used; outputs blank
    constant CHAR_R : integer := 27;
    constant CHAR_S : integer := 28;
    constant CHAR_T : integer := 29;
    constant CHAR_U : integer := 30;
    constant CHAR_V : integer := 31;
    constant CHAR_W : integer := 32;
    constant CHAR_X : integer := 33;
    constant CHAR_Y : integer := 34;
    constant CHAR_Z : integer := 35; -- not used; outputs blank

    constant CHAR_COLON  : integer := 36;
    constant CHAR_EQUALS : integer := 37;

end package;

package body game_pkg is
end package body;