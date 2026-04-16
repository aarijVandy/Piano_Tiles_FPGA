-- vga_score_display.vhd
-- Overlays the score panel on the right side of the VGA output.
--
-- Layout (all text at SCALE=4, so each character is 32x32 pixels):
--   Columns:
--     LABEL_X (696) : labels left-aligned, longest label = 5 chars (SCORE/COMBO)
--     NUM_X   (888) : 4-digit number block, right edge at PANEL_RIGHT (1016)
--     1-char gap between label right edge and number left edge
--   Rows (Y positions, with 16px inter-row gap):
--     ROW1_Y (32)  : MAX   label + max-score digits
--     ROW2_Y (80)  : SCORE label + current score digits
--     [32px blank-line gap separates score group from combo group]
--     ROW3_Y (160) : COMBO label + combo digits
--     ROW4_Y (208) : BEST  label + best-combo digits
--
-- All numbers are displayed with leading zeros (fixed 4-digit width).
-- Labels are left-aligned; number blocks are right-anchored.

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY vga_score_display IS
	GENERIC (
		SCALE    : INTEGER := 4;   -- each font pixel is SCALE x SCALE screen pixels
		CHAR_W   : INTEGER := 8;   -- font character width in pixels
		CHAR_H   : INTEGER := 8    -- font character height in pixels
	);
	PORT (
		pixel_row    : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
		pixel_column : IN STD_LOGIC_VECTOR(10 DOWNTO 0);

		-- Current score BCD digits (ones=least significant)
		score_ones      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_tens      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_hundreds  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		score_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Max (best) score BCD digits
		max_ones      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_tens      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_hundreds  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		max_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Current combo BCD digits
		combo_ones      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		combo_tens      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		combo_hundreds  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		combo_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Best combo BCD digits
		best_combo_ones      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		best_combo_tens      : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		best_combo_hundreds  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		best_combo_thousands : IN STD_LOGIC_VECTOR(3 DOWNTO 0);

		-- Incoming background RGB (from tile renderer)
		red_in   : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		green_in : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		blue_in  : IN STD_LOGIC_VECTOR(7 DOWNTO 0);

		-- Outgoing RGB
		red_out   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		green_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		blue_out  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF vga_score_display IS

	-- -------------------------------------------------------------------------
	-- Layout constants (derived from SCALE and CHAR_W/CHAR_H generics)
	-- -------------------------------------------------------------------------
	CONSTANT CHAR_PX    : INTEGER := CHAR_W * SCALE;  -- scaled char width  = 32
	CONSTANT CHAR_PY    : INTEGER := CHAR_H * SCALE;  -- scaled char height = 32

	-- Right edge of the panel (8px margin from screen edge)
	CONSTANT PANEL_RIGHT : INTEGER := 1016;

	-- Number block: 4 digits right-anchored at PANEL_RIGHT
	CONSTANT NUM_X       : INTEGER := PANEL_RIGHT - 4 * CHAR_PX;   -- 888

	-- Label block: longest label is 5 chars (SCORE / COMBO) + 1-char gap before number
	CONSTANT LABEL_X     : INTEGER := NUM_X - CHAR_PX - 5 * CHAR_PX; -- 696

	-- Row Y positions
	CONSTANT ROW1_Y : INTEGER := 32;   -- MAX   row
	CONSTANT ROW2_Y : INTEGER := 80;   -- SCORE row  (ROW1_Y + CHAR_PY + 16)
	-- 32px blank-line gap between score group and combo group
	CONSTANT ROW3_Y : INTEGER := 160;  -- COMBO row  (ROW2_Y + CHAR_PY + 16 + 32)
	CONSTANT ROW4_Y : INTEGER := 208;  -- BEST  row  (ROW3_Y + CHAR_PY + 16)

	-- -------------------------------------------------------------------------
	-- font_rom interface signals
	-- -------------------------------------------------------------------------
	SIGNAL font_char  : STD_LOGIC_VECTOR(5 DOWNTO 0) := (OTHERS => '0');
	SIGNAL font_row   : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_col   : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_pixel : STD_LOGIC;

BEGIN

	-- Single shared font_rom instance (purely combinational)
	font_inst : ENTITY work.font_rom
		PORT MAP (
			char_code => font_char,
			row       => font_row,
			col       => font_col,
			pixel     => font_pixel
		);

	-- -------------------------------------------------------------------------
	-- Main rendering process
	-- For each pixel, determine if it falls inside a label or number bounding
	-- box, look up the correct glyph, and overlay yellow text on the background.
	-- -------------------------------------------------------------------------
	PROCESS (pixel_row, pixel_column,
	         score_ones, score_tens, score_hundreds, score_thousands,
	         max_ones, max_tens, max_hundreds, max_thousands,
	         combo_ones, combo_tens, combo_hundreds, combo_thousands,
	         best_combo_ones, best_combo_tens, best_combo_hundreds, best_combo_thousands,
	         red_in, green_in, blue_in, font_pixel)

		VARIABLE p_x : INTEGER;
		VARIABLE p_y : INTEGER;

		VARIABLE draw_text  : BOOLEAN;
		VARIABLE digit_idx  : INTEGER;
		VARIABLE char_px_x  : INTEGER;
		VARIABLE char_px_y  : INTEGER;

		-- Label character sequences (left-aligned, all start at LABEL_X)
		-- MAX   = 3 chars,  SCORE/COMBO = 5 chars,  BEST = 4 chars
		CONSTANT LABEL_MAX   : char_array_t(0 TO 3) := (CHAR_M, CHAR_A, CHAR_X,   CHAR_COLON);
		CONSTANT LABEL_SCORE : char_array_t(0 TO 5) := (CHAR_S, CHAR_C, CHAR_O, CHAR_R, CHAR_E, CHAR_COLON);
		CONSTANT LABEL_COMBO : char_array_t(0 TO 5) := (CHAR_C, CHAR_O, CHAR_M, CHAR_B, CHAR_O, CHAR_COLON);
		CONSTANT LABEL_BEST  : char_array_t(0 TO 4) := (CHAR_B, CHAR_E, CHAR_S, CHAR_T,  CHAR_COLON);

	BEGIN
		p_x := to_integer(unsigned(pixel_column));
		p_y := to_integer(unsigned(pixel_row));

		draw_text := false;
		font_char <= (OTHERS => '0');

		-- Default: pass the tile-renderer background straight through
		red_out   <= red_in;
		green_out <= green_in;
		blue_out  <= blue_in;

		-- ---- ROW 1 : MAX label + max-score number ---------------------------
		IF p_y >= ROW1_Y AND p_y < ROW1_Y + CHAR_PY THEN
			char_px_y := (p_y - ROW1_Y) / SCALE;

			-- MAX: label (4 chars: M A X :)
			IF p_x >= LABEL_X AND p_x < LABEL_X + 4 * CHAR_PX THEN
				draw_text := true;
				digit_idx := (p_x - LABEL_X) / CHAR_PX;
				font_char <= STD_LOGIC_VECTOR(to_unsigned(LABEL_MAX(digit_idx), 6));
				char_px_x := ((p_x - LABEL_X) MOD CHAR_PX) / SCALE;

			-- MAX: number (4 digits, right-anchored)
			ELSIF p_x >= NUM_X AND p_x < PANEL_RIGHT THEN
				draw_text := true;
				digit_idx := (p_x - NUM_X) / CHAR_PX;
				CASE digit_idx IS
					WHEN 0 => font_char <= "00" & max_thousands;
					WHEN 1 => font_char <= "00" & max_hundreds;
					WHEN 2 => font_char <= "00" & max_tens;
					WHEN 3 => font_char <= "00" & max_ones;
					WHEN OTHERS => font_char <= (OTHERS => '0');
				END CASE;
				char_px_x := ((p_x - NUM_X) MOD CHAR_PX) / SCALE;
			END IF;
		END IF;

		-- ---- ROW 2 : SCORE label + current score number ---------------------
		IF p_y >= ROW2_Y AND p_y < ROW2_Y + CHAR_PY THEN
			char_px_y := (p_y - ROW2_Y) / SCALE;

			-- SCORE: label (6 chars: S C O R E :)
			IF p_x >= LABEL_X AND p_x < LABEL_X + 6 * CHAR_PX THEN
				draw_text := true;
				digit_idx := (p_x - LABEL_X) / CHAR_PX;
				font_char <= STD_LOGIC_VECTOR(to_unsigned(LABEL_SCORE(digit_idx), 6));
				char_px_x := ((p_x - LABEL_X) MOD CHAR_PX) / SCALE;

			-- SCORE: number (4 digits, right-anchored)
			ELSIF p_x >= NUM_X AND p_x < PANEL_RIGHT THEN
				draw_text := true;
				digit_idx := (p_x - NUM_X) / CHAR_PX;
				CASE digit_idx IS
					WHEN 0 => font_char <= "00" & score_thousands;
					WHEN 1 => font_char <= "00" & score_hundreds;
					WHEN 2 => font_char <= "00" & score_tens;
					WHEN 3 => font_char <= "00" & score_ones;
					WHEN OTHERS => font_char <= (OTHERS => '0');
				END CASE;
				char_px_x := ((p_x - NUM_X) MOD CHAR_PX) / SCALE;
			END IF;
		END IF;

		-- ---- ROW 3 : COMBO label + current combo number ---------------------
		IF p_y >= ROW3_Y AND p_y < ROW3_Y + CHAR_PY THEN
			char_px_y := (p_y - ROW3_Y) / SCALE;

			-- COMBO: label (6 chars: C O M B O :)
			IF p_x >= LABEL_X AND p_x < LABEL_X + 6 * CHAR_PX THEN
				draw_text := true;
				digit_idx := (p_x - LABEL_X) / CHAR_PX;
				font_char <= STD_LOGIC_VECTOR(to_unsigned(LABEL_COMBO(digit_idx), 6));
				char_px_x := ((p_x - LABEL_X) MOD CHAR_PX) / SCALE;

			-- COMBO: number (4 digits, right-anchored)
			ELSIF p_x >= NUM_X AND p_x < PANEL_RIGHT THEN
				draw_text := true;
				digit_idx := (p_x - NUM_X) / CHAR_PX;
				CASE digit_idx IS
					WHEN 0 => font_char <= "00" & combo_thousands;
					WHEN 1 => font_char <= "00" & combo_hundreds;
					WHEN 2 => font_char <= "00" & combo_tens;
					WHEN 3 => font_char <= "00" & combo_ones;
					WHEN OTHERS => font_char <= (OTHERS => '0');
				END CASE;
				char_px_x := ((p_x - NUM_X) MOD CHAR_PX) / SCALE;
			END IF;
		END IF;

		-- ---- ROW 4 : BEST label + best-combo number -------------------------
		IF p_y >= ROW4_Y AND p_y < ROW4_Y + CHAR_PY THEN
			char_px_y := (p_y - ROW4_Y) / SCALE;

			-- BEST: label (5 chars: B E S T :)
			IF p_x >= LABEL_X AND p_x < LABEL_X + 5 * CHAR_PX THEN
				draw_text := true;
				digit_idx := (p_x - LABEL_X) / CHAR_PX;
				font_char <= STD_LOGIC_VECTOR(to_unsigned(LABEL_BEST(digit_idx), 6));
				char_px_x := ((p_x - LABEL_X) MOD CHAR_PX) / SCALE;

			-- BEST: number (4 digits, right-anchored)
			ELSIF p_x >= NUM_X AND p_x < PANEL_RIGHT THEN
				draw_text := true;
				digit_idx := (p_x - NUM_X) / CHAR_PX;
				CASE digit_idx IS
					WHEN 0 => font_char <= "00" & best_combo_thousands;
					WHEN 1 => font_char <= "00" & best_combo_hundreds;
					WHEN 2 => font_char <= "00" & best_combo_tens;
					WHEN 3 => font_char <= "00" & best_combo_ones;
					WHEN OTHERS => font_char <= (OTHERS => '0');
				END CASE;
				char_px_x := ((p_x - NUM_X) MOD CHAR_PX) / SCALE;
			END IF;
		END IF;

		-- ---- Draw glyph pixel if inside any text region ---------------------
		IF draw_text THEN
			-- Route scaled pixel coordinates to the font ROM
			font_row <= STD_LOGIC_VECTOR(to_unsigned(char_px_y, 3));
			font_col <= STD_LOGIC_VECTOR(to_unsigned(char_px_x, 3));

			-- font_rom is purely combinational; delta-cycle iteration resolves this.
			IF font_pixel = '1' THEN
				-- Yellow text (matches the existing score text colour)
				red_out   <= x"FF";
				green_out <= x"FF";
				blue_out  <= x"00";
			END IF;
		ELSE
			-- Drive defaults to suppress latch inference
			font_row <= "000";
			font_col <= "000";
		END IF;

	END PROCESS;

END ARCHITECTURE;
