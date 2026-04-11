LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY vga_score_display IS
	GENERIC (
		SCALE : INTEGER := 4;      -- Each "pixel" in the font is 4x4 screen pixels
		CHAR_W : INTEGER := 8;     -- Font character width
		CHAR_H : INTEGER := 8;     -- Font character height
		SCORE_X : INTEGER := 864;  -- X position of current score (top right)
		SCORE_Y : INTEGER := 32;   -- Y position of current score
		MAX_X : INTEGER := 864;    -- X position of max score
		MAX_Y : INTEGER := 80      -- Y position of max score
	);
	PORT (
		pixel_row : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
		pixel_column : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
		
		-- Current score BCD
		score_ones : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_tens : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_hundreds : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Max score BCD
		max_ones : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_tens : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_hundreds : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Incoming background RGB
		red_in : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		green_in : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		blue_in : IN STD_LOGIC_VECTOR(7 DOWNTO 0);

		-- Outgoing RGB
		red_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		green_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		blue_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF vga_score_display IS

	-- Signal to connect to the font ROM
	SIGNAL font_digit : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0000";
	SIGNAL font_row : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_col : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_pixel : STD_LOGIC;

BEGIN

	-- Instantiate the single font ROM instance
	font_inst : ENTITY work.font_rom
		PORT MAP (
			digit => font_digit,
			row => font_row,
			col => font_col,
			pixel => font_pixel
		);

	PROCESS (pixel_row, pixel_column, score_ones, score_tens, score_hundreds, score_thousands, 
			 max_ones, max_tens, max_hundreds, max_thousands, red_in, green_in, blue_in, font_pixel)
		VARIABLE p_x : INTEGER;
		VARIABLE p_y : INTEGER;
		
		VARIABLE draw_text : BOOLEAN;
		VARIABLE digit_idx : INTEGER;
		VARIABLE char_px_x : INTEGER;
		VARIABLE char_px_y : INTEGER;
		
		-- Full width of a scaled character
		VARIABLE char_scaled_w : INTEGER := CHAR_W * SCALE;
		VARIABLE char_scaled_h : INTEGER := CHAR_H * SCALE;
	BEGIN
		p_x := to_integer(unsigned(pixel_column));
		p_y := to_integer(unsigned(pixel_row));

		draw_text := false;
		font_digit <= "0000";
		
		-- Default: pass through background
		red_out <= red_in;
		green_out <= green_in;
		blue_out <= blue_in;

		-- Check if we are inside the CURRENT SCORE bounding box
		-- We display 4 digits: thousands, hundreds, tens, ones
		IF p_y >= SCORE_Y AND p_y < SCORE_Y + char_scaled_h THEN
			IF p_x >= SCORE_X AND p_x < SCORE_X + (4 * char_scaled_w) THEN
				draw_text := true;
				
				-- Which of the 4 digits are we inside?
				digit_idx := (p_x - SCORE_X) / char_scaled_w;
				
				CASE digit_idx IS
					WHEN 0 => font_digit <= score_thousands;
					WHEN 1 => font_digit <= score_hundreds;
					WHEN 2 => font_digit <= score_tens;
					WHEN 3 => font_digit <= score_ones;
					WHEN OTHERS => font_digit <= "0000";
				END CASE;
				
				-- coordinate mapping relative to character 0,0
				char_px_x := ((p_x - SCORE_X) MOD char_scaled_w) / SCALE;
				char_px_y := (p_y - SCORE_Y) / SCALE;
			END IF;
		END IF;

		-- Check if we are inside the MAX SCORE bounding box
		IF p_y >= MAX_Y AND p_y < MAX_Y + char_scaled_h THEN
			IF p_x >= MAX_X AND p_x < MAX_X + (4 * char_scaled_w) THEN
				draw_text := true;
				
				digit_idx := (p_x - MAX_X) / char_scaled_w;
				
				CASE digit_idx IS
					WHEN 0 => font_digit <= max_thousands;
					WHEN 1 => font_digit <= max_hundreds;
					WHEN 2 => font_digit <= max_tens;
					WHEN 3 => font_digit <= max_ones;
					WHEN OTHERS => font_digit <= "0000";
				END CASE;
				
				char_px_x := ((p_x - MAX_X) MOD char_scaled_w) / SCALE;
				char_px_y := (p_y - MAX_Y) / SCALE;
			END IF;
		END IF;

		-- Output text overlay logic
		IF draw_text THEN
			-- Route coordinates to ROM
			font_row <= STD_LOGIC_VECTOR(to_unsigned(char_px_y, 3));
			font_col <= STD_LOGIC_VECTOR(to_unsigned(char_px_x, 3));
			
			-- The font ROM is purely combinational in our implementation, 
			-- so it resolves immediately. If the pixel is '1', draw it.
			IF font_pixel = '1' THEN
				-- Draw white text
				red_out   <= x"FF";
				green_out <= x"FF";
				blue_out  <= x"00"; -- Yellow text
			END IF;
		ELSE
			-- prevent latch inference for font mapping
			font_row <= "000";
			font_col <= "000";
		END IF;
		
	END PROCESS;

END ARCHITECTURE;
