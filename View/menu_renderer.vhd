-- menu_renderer.vhd
-- Draws the start-screen splash overlay.
--
-- Layout (screen 1024x768, centred at 512x384):
--
--   Y=280  [SCALE=4, yellow]  PIANO TILES          (title)
--   Y=344  [SCALE=2, gray]    PRESS A LANE BUTTON TO HIT THE BLACK TILE
--   Y=368  [SCALE=2, gray]    MISS OR PRESS WRONG = SCORE PENALTY
--   Y=392  [SCALE=2, gray]    SCORE PENALTY INCREASES OVER TIME
--   Y=416  [SCALE=2, gray]    SW0 = RESET GAME
--   Y=464  [SCALE=3, white/blink] PRESS ANY BUTTON TO START
--
-- Background colour: (0x44, 0x66, 0x88) — same as the game sidebar.
-- Title: bright yellow (0xFF, 0xFF, 0x00).
-- Instructions: light gray (0xCC, 0xCC, 0xCC).
-- Start prompt: white (0xFF, 0xFF, 0xFF) when blink_on='1', background when '0'.

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY menu_renderer IS
	PORT (
		pixel_row    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
		pixel_column : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
		video_on     : IN  STD_LOGIC;
		blink_on     : IN  STD_LOGIC; -- '1' = prompt visible, '0' = prompt hidden

		red_out   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		green_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		blue_out  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF menu_renderer IS

	-- -------------------------------------------------------------------------
	-- font_rom signals (purely combinational, shared across all text regions)
	-- -------------------------------------------------------------------------
	SIGNAL font_char  : STD_LOGIC_VECTOR(5 DOWNTO 0) := (OTHERS => '0');
	SIGNAL font_row_s : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_col_s : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	SIGNAL font_pixel : STD_LOGIC;

BEGIN

	-- font_rom is instantiated once; the rendering process drives char/row/col
	font_inst : ENTITY work.font_rom
		PORT MAP (
			char_code => font_char,
			row       => font_row_s,
			col       => font_col_s,
			pixel     => font_pixel
		);

	-- -------------------------------------------------------------------------
	-- Rendering process
	-- Each named section handles one line of text at a specific scale.
	-- Scales used:
	--   SCALE_T = 4  -> 32x32px/char  (title)
	--   SCALE_I = 2  -> 16x16px/char  (instructions)
	--   SCALE_S = 3  -> 24x24px/char  (start prompt)
	--
	-- Horizontal centering: for a line of N chars at scale K,
	--   x_start = 512 - (N * 8 * K) / 2
	-- -------------------------------------------------------------------------
	PROCESS (pixel_row, pixel_column, blink_on, video_on, font_pixel)

		VARIABLE p_x : INTEGER;
		VARIABLE p_y : INTEGER;
		VARIABLE draw_text   : BOOLEAN;
		VARIABLE text_colour : STD_LOGIC_VECTOR(23 DOWNTO 0); -- RGB packed
		VARIABLE char_idx    : INTEGER;
		VARIABLE cpx         : INTEGER; -- character pixel x within glyph
		VARIABLE cpy         : INTEGER; -- character pixel y within glyph

		-- ---- Title: "PIANO TILES"  (11 chars, SCALE=4, x_start=336, y=280) ----
		CONSTANT SCALE_T : INTEGER := 4;
		CONSTANT TITLE_Y : INTEGER := 280;
		CONSTANT TITLE_X : INTEGER := 512 - (11 * 8 * SCALE_T) / 2; -- 336
		CONSTANT TITLE_LEN : INTEGER := 11;
		CONSTANT TITLE_TEXT : char_array_t(0 TO 10) := (
			CHAR_P, CHAR_I, CHAR_A, CHAR_N, CHAR_O,
			CHAR_SPACE,
			CHAR_T, CHAR_I, CHAR_L, CHAR_E, CHAR_S
		);

		-- ---- Instructions (SCALE=2, x centred per line) ---------------------

		CONSTANT SCALE_I : INTEGER := 2;

		-- "PRESS A LANE BUTTON TO HIT THE BLACK TILE"  (41 chars, x=184, y=344)
		CONSTANT I1_LEN : INTEGER := 41;
		CONSTANT I1_Y   : INTEGER := 344;
		CONSTANT I1_X   : INTEGER := 512 - (I1_LEN * 8 * SCALE_I) / 2;
		CONSTANT I1_TEXT : char_array_t(0 TO 40) := (
			CHAR_P, CHAR_R, CHAR_E, CHAR_S, CHAR_S, CHAR_SPACE,
			CHAR_A, CHAR_SPACE,
			CHAR_L, CHAR_A, CHAR_N, CHAR_E, CHAR_SPACE,
			CHAR_B, CHAR_U, CHAR_T, CHAR_T, CHAR_O, CHAR_N, CHAR_SPACE,
			CHAR_T, CHAR_O, CHAR_SPACE,
			CHAR_H, CHAR_I, CHAR_T, CHAR_SPACE,
			CHAR_T, CHAR_H, CHAR_E, CHAR_SPACE,
			CHAR_B, CHAR_L, CHAR_A, CHAR_C, CHAR_K, CHAR_SPACE,
			CHAR_T, CHAR_I, CHAR_L, CHAR_E
		);

		-- "MISS OR PRESS WRONG = SCORE PENALTY"  (35 chars, x=232, y=368)
		CONSTANT I2_LEN : INTEGER := 35;
		CONSTANT I2_Y   : INTEGER := 368;
		CONSTANT I2_X   : INTEGER := 512 - (I2_LEN * 8 * SCALE_I) / 2;
		CONSTANT I2_TEXT : char_array_t(0 TO 34) := (
			CHAR_M, CHAR_I, CHAR_S, CHAR_S, CHAR_SPACE,
			CHAR_O, CHAR_R, CHAR_SPACE,
			CHAR_P, CHAR_R, CHAR_E, CHAR_S, CHAR_S, CHAR_SPACE,
			CHAR_W, CHAR_R, CHAR_O, CHAR_N, CHAR_G, CHAR_SPACE,
			CHAR_EQUALS, CHAR_SPACE,
			CHAR_S, CHAR_C, CHAR_O, CHAR_R, CHAR_E, CHAR_SPACE,
			CHAR_P, CHAR_E, CHAR_N, CHAR_A, CHAR_L, CHAR_T, CHAR_Y
		);

		-- "SCORE PENALTY INCREASES OVER TIME"  (33 chars, x=248, y=392)
		CONSTANT I3_LEN : INTEGER := 33;
		CONSTANT I3_Y   : INTEGER := 392;
		CONSTANT I3_X   : INTEGER := 512 - (I3_LEN * 8 * SCALE_I) / 2;
		CONSTANT I3_TEXT : char_array_t(0 TO 32) := (
			CHAR_S, CHAR_C, CHAR_O, CHAR_R, CHAR_E, CHAR_SPACE,
			CHAR_P, CHAR_E, CHAR_N, CHAR_A, CHAR_L, CHAR_T, CHAR_Y, CHAR_SPACE,
			CHAR_I, CHAR_N, CHAR_C, CHAR_R, CHAR_E, CHAR_A, CHAR_S, CHAR_E, CHAR_S, CHAR_SPACE,
			CHAR_O, CHAR_V, CHAR_E, CHAR_R, CHAR_SPACE,
			CHAR_T, CHAR_I, CHAR_M, CHAR_E
		);

		-- "SW0 = RESET GAME"  (16 chars, x=384, y=416)
		CONSTANT I4_LEN : INTEGER := 16;
		CONSTANT I4_Y   : INTEGER := 416;
		CONSTANT I4_X   : INTEGER := 512 - (I4_LEN * 8 * SCALE_I) / 2;
		CONSTANT I4_TEXT : char_array_t(0 TO 15) := (
			-- '0' digit is encoded as integer 0
			CHAR_S, CHAR_W, 0, CHAR_SPACE,
			CHAR_EQUALS, CHAR_SPACE,
			CHAR_R, CHAR_E, CHAR_S, CHAR_E, CHAR_T, CHAR_SPACE,
			CHAR_G, CHAR_A, CHAR_M, CHAR_E
		);

		-- ---- Start prompt: "PRESS ANY BUTTON TO START" (25 chars, SCALE=3, y=464) ---
		CONSTANT SCALE_S : INTEGER := 3;
		CONSTANT PROMPT_LEN : INTEGER := 25;
		CONSTANT PROMPT_Y : INTEGER := 464;
		CONSTANT PROMPT_X : INTEGER := 512 - (PROMPT_LEN * 8 * SCALE_S) / 2; -- 212
		CONSTANT PROMPT_TEXT : char_array_t(0 TO 24) := (
			CHAR_P, CHAR_R, CHAR_E, CHAR_S, CHAR_S, CHAR_SPACE,
			CHAR_A, CHAR_N, CHAR_Y, CHAR_SPACE,
			CHAR_B, CHAR_U, CHAR_T, CHAR_T, CHAR_O, CHAR_N, CHAR_SPACE,
			CHAR_T, CHAR_O, CHAR_SPACE,
			CHAR_S, CHAR_T, CHAR_A, CHAR_R, CHAR_T
		);

	BEGIN
		p_x := to_integer(unsigned(pixel_column));
		p_y := to_integer(unsigned(pixel_row));

		draw_text   := false;
		text_colour := x"FFFFFF"; -- default white (overridden per region)
		font_char   <= (OTHERS => '0');
		-- Initialize to 0 in all paths to prevent latch inference
		cpx := 0;
		cpy := 0;

		-- Background: same blue-gray as the game sidebar
		red_out   <= x"44";
		green_out <= x"66";
		blue_out  <= x"88";

		IF video_on = '1' THEN

			-- ---- Title line (SCALE=4, yellow) --------------------------------
			IF p_y >= TITLE_Y AND p_y < TITLE_Y + 8 * SCALE_T THEN
				IF p_x >= TITLE_X AND p_x < TITLE_X + TITLE_LEN * 8 * SCALE_T THEN
					char_idx := (p_x - TITLE_X) / (8 * SCALE_T);
					IF TITLE_TEXT(char_idx) /= CHAR_SPACE THEN
						draw_text   := true;
						text_colour := x"FFFF00"; -- bright yellow
						font_char   <= STD_LOGIC_VECTOR(to_unsigned(TITLE_TEXT(char_idx), 6));
						cpx := ((p_x - TITLE_X) MOD (8 * SCALE_T)) / SCALE_T;
						cpy := (p_y - TITLE_Y)                       / SCALE_T;
					END IF;
				END IF;
			END IF;

			-- ---- Instruction line 1 (SCALE=2, gray) --------------------------
			IF p_y >= I1_Y AND p_y < I1_Y + 8 * SCALE_I THEN
				IF p_x >= I1_X AND p_x < I1_X + I1_LEN * 8 * SCALE_I THEN
					char_idx := (p_x - I1_X) / (8 * SCALE_I);
					IF I1_TEXT(char_idx) /= CHAR_SPACE THEN
						draw_text   := true;
						text_colour := x"CCCCCC"; -- light gray
						font_char   <= STD_LOGIC_VECTOR(to_unsigned(I1_TEXT(char_idx), 6));
						cpx := ((p_x - I1_X) MOD (8 * SCALE_I)) / SCALE_I;
						cpy := (p_y - I1_Y)                       / SCALE_I;
					END IF;
				END IF;
			END IF;

			-- ---- Instruction line 2 (SCALE=2, gray) --------------------------
			IF p_y >= I2_Y AND p_y < I2_Y + 8 * SCALE_I THEN
				IF p_x >= I2_X AND p_x < I2_X + I2_LEN * 8 * SCALE_I THEN
					char_idx := (p_x - I2_X) / (8 * SCALE_I);
					IF I2_TEXT(char_idx) /= CHAR_SPACE THEN
						draw_text   := true;
						text_colour := x"CCCCCC";
						font_char   <= STD_LOGIC_VECTOR(to_unsigned(I2_TEXT(char_idx), 6));
						cpx := ((p_x - I2_X) MOD (8 * SCALE_I)) / SCALE_I;
						cpy := (p_y - I2_Y)                       / SCALE_I;
					END IF;
				END IF;
			END IF;

			-- ---- Instruction line 3 (SCALE=2, gray) --------------------------
			IF p_y >= I3_Y AND p_y < I3_Y + 8 * SCALE_I THEN
				IF p_x >= I3_X AND p_x < I3_X + I3_LEN * 8 * SCALE_I THEN
					char_idx := (p_x - I3_X) / (8 * SCALE_I);
					IF I3_TEXT(char_idx) /= CHAR_SPACE THEN
						draw_text   := true;
						text_colour := x"CCCCCC";
						font_char   <= STD_LOGIC_VECTOR(to_unsigned(I3_TEXT(char_idx), 6));
						cpx := ((p_x - I3_X) MOD (8 * SCALE_I)) / SCALE_I;
						cpy := (p_y - I3_Y)                       / SCALE_I;
					END IF;
				END IF;
			END IF;

			-- ---- Instruction line 4 (SCALE=2, gray) --------------------------
			IF p_y >= I4_Y AND p_y < I4_Y + 8 * SCALE_I THEN
				IF p_x >= I4_X AND p_x < I4_X + I4_LEN * 8 * SCALE_I THEN
					char_idx := (p_x - I4_X) / (8 * SCALE_I);
					IF I4_TEXT(char_idx) /= CHAR_SPACE THEN
						draw_text   := true;
						text_colour := x"CCCCCC";
						font_char   <= STD_LOGIC_VECTOR(to_unsigned(I4_TEXT(char_idx), 6));
						cpx := ((p_x - I4_X) MOD (8 * SCALE_I)) / SCALE_I;
						cpy := (p_y - I4_Y)                       / SCALE_I;
					END IF;
				END IF;
			END IF;

			-- ---- Start prompt (SCALE=3, white, blink_on-gated) ---------------
			IF blink_on = '1' THEN
				IF p_y >= PROMPT_Y AND p_y < PROMPT_Y + 8 * SCALE_S THEN
					IF p_x >= PROMPT_X AND p_x < PROMPT_X + PROMPT_LEN * 8 * SCALE_S THEN
						char_idx := (p_x - PROMPT_X) / (8 * SCALE_S);
						IF PROMPT_TEXT(char_idx) /= CHAR_SPACE THEN
							draw_text   := true;
							text_colour := x"FFFFFF"; -- bright white
							font_char   <= STD_LOGIC_VECTOR(to_unsigned(PROMPT_TEXT(char_idx), 6));
							cpx := ((p_x - PROMPT_X) MOD (8 * SCALE_S)) / SCALE_S;
							cpy := (p_y - PROMPT_Y)                       / SCALE_S;
						END IF;
					END IF;
				END IF;
			END IF;

			-- ---- Composite: drive font ROM and paint pixel if set -----------
			IF draw_text THEN
				font_row_s <= STD_LOGIC_VECTOR(to_unsigned(cpy, 3));
				font_col_s <= STD_LOGIC_VECTOR(to_unsigned(cpx, 3));

				-- font_rom is purely combinational; this reads the resolved output.
				IF font_pixel = '1' THEN
					red_out   <= text_colour(23 DOWNTO 16);
					green_out <= text_colour(15 DOWNTO 8);
					blue_out  <= text_colour(7  DOWNTO 0);
				END IF;
			ELSE
				-- Suppress latch inference for unused ROM control signals
				font_row_s <= "000";
				font_col_s <= "000";
			END IF;

		END IF; -- video_on

	END PROCESS;

END ARCHITECTURE;
