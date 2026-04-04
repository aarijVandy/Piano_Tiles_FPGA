library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tile is 
    Port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        freq_tick    : in  std_logic;  -- controls falling speed
        pixel_row    : in  unsigned(10 downto 0);
        pixel_column : in  unsigned(10 downto 0);
        rand_col     : in  unsigned(1 downto 0);   -- random value 0..3
        tile_on      : out std_logic
    );
end tile;

architecture behavior of tile is
    constant SCREEN_WIDTH  : integer := 1024;
    constant SCREEN_HEIGHT : integer := 768;
    constant NUM_COLS      : integer := 4;
    constant COL_WIDTH     : integer := 256;  -- 1024 / 4
    constant TILE_HEIGHT   : integer := 64;

    signal tile_x : unsigned(10 downto 0) := to_unsigned(0, 11);
    signal tile_y : unsigned(10 downto 0) := to_unsigned(0, 11);

begin

    Move_Tile: process(clk, reset)
        variable next_x : integer;
    begin
        if reset = '1' then
            tile_y <= to_unsigned(0, 11);
            tile_x <= to_unsigned(0, 11);

        elsif rising_edge(clk) then
            if freq_tick = '1' then
                if to_integer(tile_y) + TILE_HEIGHT >= SCREEN_HEIGHT then
                    tile_y <= to_unsigned(0, 11);

                    next_x := to_integer(rand_col) * COL_WIDTH;
                    tile_x <= to_unsigned(next_x, 11);
                else
                    tile_y <= tile_y + to_unsigned(8, 11); -- todo: change to change speed
                end if;
            end if;
        end if;
    end process Move_Tile;

    Display_Tile: process(pixel_row, pixel_column, tile_x, tile_y)
    begin
        if (pixel_column >= tile_x) and
           (pixel_column < tile_x + to_unsigned(COL_WIDTH, 11)) and
           (pixel_row >= tile_y) and
           (pixel_row < tile_y + to_unsigned(8, 11)) then -- todo: change to change speed
            tile_on <= '1';
        else
            tile_on <= '0';
        end if;
    end process Display_Tile;

end behavior;