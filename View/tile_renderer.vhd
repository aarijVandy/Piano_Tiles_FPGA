LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.NUMERIC_STD.all;
USE work.game_pkg.all;

ENTITY tile_renderer IS
    PORT(
        pixel_row    : IN std_logic_vector(10 DOWNTO 0);
        pixel_column : IN std_logic_vector(10 DOWNTO 0);
        notes_matrix : IN note_matrix_t;
        hit_matrix   : IN note_matrix_t;
        note_offset  : IN integer range 0 to NOTE_HEIGHT;
        Red          : OUT std_logic_vector(7 downto 0);
        Green        : OUT std_logic_vector(7 downto 0);
        Blue         : OUT std_logic_vector(7 downto 0);
        video_on     : IN std_logic
    );
END tile_renderer;

ARCHITECTURE behavior OF tile_renderer IS
    CONSTANT LANE_START_X : integer := (SCREEN_WIDTH / 2) - ((LANE_COUNT * LANE_WIDTH) / 2);
    CONSTANT LANE_END_X   : integer := LANE_START_X + (LANE_COUNT * LANE_WIDTH);
    CONSTANT NOTE_PX_H    : integer := SCREEN_HEIGHT / NOTE_COUNT;
BEGIN
    PROCESS (pixel_column, pixel_row, notes_matrix, hit_matrix, note_offset, video_on)
        VARIABLE p_x : integer;
        VARIABLE p_y : integer;
        VARIABLE lane_idx : integer;
        VARIABLE note_idx : integer;
        VARIABLE y_offset : integer;
        VARIABLE effective_y : integer;
    BEGIN
        IF video_on = '1' THEN
            p_x := to_integer(unsigned(pixel_column));
            p_y := to_integer(unsigned(pixel_row));

            y_offset := (note_offset * NOTE_PX_H) / NOTE_HEIGHT;
            effective_y := p_y - y_offset;

            IF p_x >= LANE_START_X AND p_x < LANE_END_X THEN
                lane_idx := (p_x - LANE_START_X) / LANE_WIDTH;

                IF effective_y >= 0 THEN
                    note_idx := effective_y / NOTE_PX_H;
                ELSE
                    note_idx := -1;
                END IF;

                -- Draw lanes and notes
                IF note_idx >= 0 AND note_idx < NOTE_COUNT THEN
                    IF notes_matrix(lane_idx)(note_idx) = '1' THEN
                        IF hit_matrix(lane_idx)(note_idx) = '1' THEN
                            -- Draw hit note (Gray)
                            Red   <= x"88";
                            Green <= x"88";
                            Blue  <= x"88";
                        ELSE
                            -- Draw active note (Black)
                            Red   <= x"00";
                            Green <= x"00";
                            Blue  <= x"00";
                        END IF;
                    ELSE
                        -- Draw empty lane (White)
                        Red   <= x"FF";
                        Green <= x"FF";
                        Blue  <= x"FF";
                    END IF;
                ELSE
                    -- empty space at the top above the scrolling note
                    Red   <= x"EE";
                    Green <= x"EE";
                    Blue  <= x"EE";
                END IF;

                -- Draw lane dividers
                IF (p_x - LANE_START_X) mod LANE_WIDTH = 0 THEN
                    Red   <= x"33";
                    Green <= x"33";
                    Blue  <= x"33";
                END IF;

            ELSE
                -- Background outside lanes (Gray bg)
                Red   <= x"44";
                Green <= x"66";
                Blue  <= x"88";
            END IF;
        ELSE
            Red   <= (others => '0');
            Green <= (others => '0');
            Blue  <= (others => '0');
        END IF;
    END PROCESS;

END behavior;
