-- game_pkg.vhd
library ieee;
use ieee.std_logic_1164.all;

package game_pkg is

    -- screen
    constant SCREEN_WIDTH  : integer := 1024;
    constant SCREEN_HEIGHT : integer := 768;

    -- lanes
    constant LANE_COUNT    : integer := 4;
    constant LANE_WIDTH    : integer := 60;

    -- notes
    constant NOTE_COUNT    : integer := 8;
    constant NOTE_HEIGHT   : integer := 20;
    -- constant NOTE_SPEED    : integer := 4;


	type note_matrix_t is array (0 to LANE_COUNT-1) of std_logic_vector(NOTE_COUNT-1 downto 0);

end package;

package body game_pkg is
end package body;