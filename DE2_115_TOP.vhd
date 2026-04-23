--
-- DE2-115 top-level module (entity declaration)
--
-- William H. Robinson, Vanderbilt University University
--   william.h.robinson@vanderbilt.edu
--
-- Updated from the DE2 top-level module created by
-- Stephen A. Edwards, Columbia University, sedwards@cs.columbia.edu
--

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY DE2_115_TOP IS
	PORT (
		-- Clocks

		CLOCK_50 : IN STD_LOGIC; -- 50 MHz
		CLOCK2_50 : IN STD_LOGIC; -- 50 MHz
		CLOCK3_50 : IN STD_LOGIC; -- 50 MHz
		SMA_CLKIN : IN STD_LOGIC; -- External Clock Input
		SMA_CLKOUT : OUT STD_LOGIC; -- External Clock Output

		-- Buttons and switches

		KEY : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- Push buttons
		SW : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- DPDT switches

		-- LED displays

		HEX0 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX1 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX2 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX3 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX4 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX5 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX6 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		HEX7 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
		LEDG : OUT STD_LOGIC_VECTOR(8 DOWNTO 0); -- Green LEDs (active high)
		LEDR : OUT STD_LOGIC_VECTOR(17 DOWNTO 0); -- Red LEDs (active high)

		-- RS-232 interface

		UART_CTS : OUT STD_LOGIC; -- UART Clear to Send
		UART_RTS : IN STD_LOGIC; -- UART Request to Send
		UART_RXD : IN STD_LOGIC; -- UART Receiver
		UART_TXD : OUT STD_LOGIC; -- UART Transmitter

		-- 16 X 2 LCD Module

		LCD_BLON : OUT STD_LOGIC; -- Back Light ON/OFF
		LCD_EN : OUT STD_LOGIC; -- Enable
		LCD_ON : OUT STD_LOGIC; -- Power ON/OFF
		LCD_RS : OUT STD_LOGIC; -- Command/Data Select, 0 = Command, 1 = Data
		LCD_RW : OUT STD_LOGIC; -- Read/Write Select, 0 = Write, 1 = Read
		LCD_DATA : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data bus 8 bits

		-- PS/2 ports

		PS2_CLK : INOUT STD_LOGIC; -- Clock
		PS2_DAT : INOUT STD_LOGIC; -- Data

		PS2_CLK2 : INOUT STD_LOGIC; -- Clock
		PS2_DAT2 : INOUT STD_LOGIC; -- Data

		-- VGA output

		VGA_BLANK_N : OUT STD_LOGIC; -- BLANK
		VGA_CLK : OUT STD_LOGIC; -- Clock
		VGA_HS : OUT STD_LOGIC; -- H_SYNC
		VGA_SYNC_N : OUT STD_LOGIC; -- SYNC
		VGA_VS : OUT STD_LOGIC; -- V_SYNC
		VGA_R : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Red[9:0]
		VGA_G : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Green[9:0]
		VGA_B : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Blue[9:0]

		-- SRAM

		SRAM_ADDR : OUT unsigned(19 DOWNTO 0); -- Address bus 20 Bits
		SRAM_DQ : INOUT unsigned(15 DOWNTO 0); -- Data bus 16 Bits
		SRAM_CE_N : OUT STD_LOGIC; -- Chip Enable
		SRAM_LB_N : OUT STD_LOGIC; -- Low-byte Data Mask
		SRAM_OE_N : OUT STD_LOGIC; -- Output Enable
		SRAM_UB_N : OUT STD_LOGIC; -- High-byte Data Mask
		SRAM_WE_N : OUT STD_LOGIC; -- Write Enable

		-- Audio CODEC

		AUD_ADCDAT : IN STD_LOGIC; -- ADC Data
		AUD_ADCLRCK : INOUT STD_LOGIC; -- ADC LR Clock
		AUD_BCLK : INOUT STD_LOGIC; -- Bit-Stream Clock
		AUD_DACDAT : OUT STD_LOGIC; -- DAC Data
		AUD_DACLRCK : INOUT STD_LOGIC; -- DAC LR Clock
		AUD_XCK : OUT STD_LOGIC; -- Chip Clock

		-- I2C for audio codec config

		I2C_SCLK : OUT STD_LOGIC;
		I2C_SDAT : INOUT STD_LOGIC;

		-- SDRAM (two 8M x 16 x 4-bank chips share command/address bus;
		-- chip 0 is DQ[15:0], chip 1 is DQ[31:16])

		DRAM_CLK   : OUT STD_LOGIC;
		DRAM_CKE   : OUT STD_LOGIC;
		DRAM_CS_N  : OUT STD_LOGIC;
		DRAM_RAS_N : OUT STD_LOGIC;
		DRAM_CAS_N : OUT STD_LOGIC;
		DRAM_WE_N  : OUT STD_LOGIC;
		DRAM_BA    : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
		DRAM_ADDR  : OUT STD_LOGIC_VECTOR(12 DOWNTO 0);
		DRAM_DQM   : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		DRAM_DQ    : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0)

	);

END DE2_115_TOP;

ARCHITECTURE structural OF DE2_115_TOP IS

	-- Component declarations
	COMPONENT note_stage IS
		PORT (
			game_tick    : IN  STD_LOGIC;
			reset_game   : IN  STD_LOGIC;
			buttons      : IN  STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);
			notes_matrix : OUT note_matrix_t;
			hit_matrix   : OUT note_matrix_t;
			score        : OUT INTEGER;
			max_score    : OUT INTEGER;
			combo        : OUT INTEGER;
			best_combo   : OUT INTEGER;
			note_offset  : OUT INTEGER RANGE 0 TO NOTE_HEIGHT
		);
	END COMPONENT;

	COMPONENT bcd7seg IS
		PORT (
			bcd : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
			seg : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT VGA_SYNC_module IS
		PORT (
			clock_50Mhz   : IN  STD_LOGIC;
			red           : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
			green         : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
			blue          : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
			red_out       : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			green_out     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			blue_out      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			horiz_sync_out: OUT STD_LOGIC;
			vert_sync_out : OUT STD_LOGIC;
			video_on      : OUT STD_LOGIC;
			pixel_clock   : OUT STD_LOGIC;
			pixel_row     : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
			pixel_column  : OUT STD_LOGIC_VECTOR(10 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT tile_renderer IS
		PORT (
			pixel_row    : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
			pixel_column : IN  STD_LOGIC_VECTOR(10 DOWNTO 0);
			notes_matrix : IN  note_matrix_t;
			hit_matrix   : IN  note_matrix_t;
			note_offset  : IN  INTEGER RANGE 0 TO NOTE_HEIGHT;
			Red          : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			Green        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			Blue         : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			video_on     : IN  STD_LOGIC
		);
	END COMPONENT;

	-- -------------------------------------------------------------------------
	-- Game state FSM type
	-- -------------------------------------------------------------------------
	TYPE game_state_t IS (MENU, PLAYING);

	-- Internal signals
	SIGNAL game_tick : STD_LOGIC;

	-- Debounced button signals (active high)
	SIGNAL buttons_debounced : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Note stage outputs
	SIGNAL notes_matrix : note_matrix_t;
	SIGNAL hit_matrix   : note_matrix_t;
	SIGNAL score        : INTEGER;
	SIGNAL note_offset  : INTEGER RANGE 0 TO NOTE_HEIGHT;

	-- Score reset / SW0 edge detection
	SIGNAL reset_game_tick : STD_LOGIC := '0';
	SIGNAL reset_pending   : STD_LOGIC := '0';
	SIGNAL sw0_prev        : STD_LOGIC := '0';

	-- Game state: MENU (splash screen) or PLAYING
	SIGNAL game_state  : game_state_t := MENU;

	-- Blink counter for the "PRESS ANY BUTTON TO START" prompt (~1 Hz toggle)
	-- game_tick = vsync ≈ 60 Hz; toggle every 30 ticks for 0.5s on / 0.5s off
	SIGNAL blink_counter : INTEGER RANGE 0 TO 59 := 0;
	SIGNAL blink_on      : STD_LOGIC := '1';

	-- Any of the four lane buttons pressed (used to start the game from menu)
	SIGNAL any_button_pressed : STD_LOGIC;

        -- VGA Signals
        SIGNAL red_int        : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL green_int      : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL blue_int       : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_r_int      : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_g_int      : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_b_int      : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL video_on_int   : STD_LOGIC;
        SIGNAL vert_sync_int  : STD_LOGIC;
        SIGNAL horiz_sync_int : STD_LOGIC;
        SIGNAL pixel_clock_int   : STD_LOGIC;
        SIGNAL pixel_row_int     : STD_LOGIC_VECTOR(10 DOWNTO 0);
        SIGNAL pixel_column_int  : STD_LOGIC_VECTOR(10 DOWNTO 0);

	-- Score BCD conversion signals
	SIGNAL score_ones      : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_tens      : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_hundreds  : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_thousands : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Max score signals
	SIGNAL max_score      : INTEGER;
	SIGNAL max_ones       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL max_tens       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL max_hundreds   : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL max_thousands  : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Combo signals
	SIGNAL combo            : INTEGER;
	SIGNAL combo_ones       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL combo_tens       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL combo_hundreds   : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL combo_thousands  : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Best combo signals
	SIGNAL best_combo            : INTEGER;
	SIGNAL best_combo_ones       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL best_combo_tens       : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL best_combo_hundreds   : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL best_combo_thousands  : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Tile renderer RGB output
	SIGNAL tile_r : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL tile_g : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL tile_b : STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- Score display RGB output (overlaid on tile renderer)
	SIGNAL score_display_r : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL score_display_g : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL score_display_b : STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- Menu renderer RGB output
	SIGNAL menu_r : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL menu_g : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL menu_b : STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- Audio gate: '1' while game_state = PLAYING
	SIGNAL playing_sig : STD_LOGIC;

BEGIN

	-- Use vertical sync as the game tick so game logic updates once per frame,
	-- during blanking, in lock-step with the display (eliminates tearing/jitter)
	game_tick <= vert_sync_int;

	-- -------------------------------------------------------------------------
	-- Any lane button pressed (active-high after debounce)
	-- Used to start the game from the menu screen
	-- -------------------------------------------------------------------------
	any_button_pressed <= buttons_debounced(0) OR buttons_debounced(1)
	                   OR buttons_debounced(2) OR buttons_debounced(3);

	-- -------------------------------------------------------------------------
	-- Game state FSM + blink counter + SW0 toggle reset
	-- Runs on game_tick (vsync ≈ 60 Hz)
	-- -------------------------------------------------------------------------
	PROCESS (game_tick)
	BEGIN
		IF rising_edge(game_tick) THEN
			reset_game_tick <= '0'; -- pulse for one tick only

			-- ---- Blink counter (drives the PRESS ANY BUTTON TO START prompt) --
			IF blink_counter = 29 THEN
				blink_counter <= 0;
				blink_on      <= NOT blink_on; -- toggle every ~0.5 s
			ELSE
				blink_counter <= blink_counter + 1;
			END IF;

			-- ---- SW0 any-edge detection: every toggle triggers a reset -------
			IF SW(0) /= sw0_prev THEN
				reset_pending <= '1';
			END IF;
			sw0_prev <= SW(0);

			-- ---- Flush the reset pulse --------------------------------------
			IF reset_pending = '1' THEN
				reset_game_tick <= '1';
				reset_pending   <= '0';
				game_state      <= MENU; -- always return to menu on reset
			END IF;

			-- ---- State transitions ------------------------------------------
			CASE game_state IS
				WHEN MENU =>
					-- Any lane button starts the game
					IF any_button_pressed = '1' THEN
						game_state      <= PLAYING;
						reset_game_tick <= '1'; -- clear any leftover tile state
					END IF;

				WHEN PLAYING =>
					-- Game runs normally; SW0 toggle handled above returns to MENU
					NULL;
			END CASE;
		END IF;
	END PROCESS;

	-- -------------------------------------------------------------------------
	-- Active-low KEY buttons -> active-high debounced signals
	-- -------------------------------------------------------------------------
	buttons_debounced(3) <= '1' WHEN KEY(0) = '0' ELSE '0';
	buttons_debounced(2) <= '1' WHEN KEY(1) = '0' ELSE '0';
	buttons_debounced(1) <= '1' WHEN KEY(2) = '0' ELSE '0';
	buttons_debounced(0) <= '1' WHEN KEY(3) = '0' ELSE '0';

	-- -------------------------------------------------------------------------
	-- Note stage: game logic (only runs properly while in PLAYING state)
	-- -------------------------------------------------------------------------
	note_stage_inst : note_stage
		PORT MAP(
			game_tick    => game_tick,
			reset_game   => reset_game_tick,
			buttons      => buttons_debounced,
			notes_matrix => notes_matrix,
			hit_matrix   => hit_matrix,
			score        => score,
			max_score    => max_score,
			combo        => combo,
			best_combo   => best_combo,
			note_offset  => note_offset
		);

	-- MAP NOTES TO LEDS (shows which lane has an active bottom tile)
	LEDG(0) <= notes_matrix(0)(NOTE_COUNT - 1);
	LEDG(1) <= notes_matrix(1)(NOTE_COUNT - 1);
	LEDG(2) <= notes_matrix(2)(NOTE_COUNT - 1);
	LEDG(3) <= notes_matrix(3)(NOTE_COUNT - 1);
	LEDG(8 DOWNTO 4) <= (OTHERS => '0'); -- Unused

	-- -------------------------------------------------------------------------
	-- BCD CONVERSIONS  (score, max_score, combo, best_combo)
	-- -------------------------------------------------------------------------
	score_bcd_inst : ENTITY work.score_to_bcd
		PORT MAP(score => score, ones => score_ones, tens => score_tens,
		         hundreds => score_hundreds, thousands => score_thousands);

	max_score_bcd_inst : ENTITY work.score_to_bcd
		PORT MAP(score => max_score, ones => max_ones, tens => max_tens,
		         hundreds => max_hundreds, thousands => max_thousands);

	combo_bcd_inst : ENTITY work.score_to_bcd
		PORT MAP(score => combo, ones => combo_ones, tens => combo_tens,
		         hundreds => combo_hundreds, thousands => combo_thousands);

	best_combo_bcd_inst : ENTITY work.score_to_bcd
		PORT MAP(score => best_combo, ones => best_combo_ones, tens => best_combo_tens,
		         hundreds => best_combo_hundreds, thousands => best_combo_thousands);

	-- -------------------------------------------------------------------------
	-- BCD TO 7-SEGMENT DECODERS (score on HEX0-3)
	-- -------------------------------------------------------------------------
	bcd7seg_ones : bcd7seg PORT MAP(bcd => score_ones,      seg => HEX0);
	bcd7seg_tens : bcd7seg PORT MAP(bcd => score_tens,      seg => HEX1);
	bcd7seg_hund : bcd7seg PORT MAP(bcd => score_hundreds,  seg => HEX2);
	bcd7seg_thou : bcd7seg PORT MAP(bcd => score_thousands, seg => HEX3);

	HEX4 <= (OTHERS => '1'); -- Turn off
	HEX5 <= (OTHERS => '1'); -- Turn off
	HEX6 <= (OTHERS => '1'); -- Turn off
	HEX7 <= (OTHERS => '1'); -- Turn off

	LEDR <= (OTHERS => '0'); -- Unused

	-- Other board outputs (tie off if not used)
	UART_TXD   <= '0';
	UART_CTS   <= '1';
	SMA_CLKOUT <= '0';
	LCD_ON     <= '0';
	LCD_BLON   <= '0';
	LCD_EN     <= '0';
	LCD_RS     <= '0';
	LCD_RW     <= '1';

	-- -------------------------------------------------------------------------
	-- Audio pipeline: WAV stored in SDRAM, played back through the WM8731
	-- whenever the game is in the PLAYING state. Menu = silence.
	-- -------------------------------------------------------------------------
	playing_sig <= '1' WHEN game_state = PLAYING ELSE '0';

	-- Audio resets only at power-up (via VHDL signal init values). The
	-- game-reset button is NOT wired here: re-initializing the SDRAM
	-- would drop the loaded song. MENU/PLAYING transitions handle
	-- start/stop and rewind through the `playing` gate.
	audio_inst : ENTITY work.audio_top
		PORT MAP(
			clk_50      => CLOCK_50,
			reset       => '0',
			playing     => playing_sig,

			aud_xck     => AUD_XCK,
			aud_bclk    => AUD_BCLK,
			aud_daclrck => AUD_DACLRCK,
			aud_dacdat  => AUD_DACDAT,
			i2c_sclk    => I2C_SCLK,
			i2c_sdat    => I2C_SDAT,

			dram_clk    => DRAM_CLK,
			dram_cke    => DRAM_CKE,
			dram_cs_n   => DRAM_CS_N,
			dram_ras_n  => DRAM_RAS_N,
			dram_cas_n  => DRAM_CAS_N,
			dram_we_n   => DRAM_WE_N,
			dram_ba     => DRAM_BA,
			dram_addr   => DRAM_ADDR,
			dram_dqm    => DRAM_DQM,
			dram_dq     => DRAM_DQ
		);

	-- -------------------------------------------------------------------------
	-- VGA sync module
	-- -------------------------------------------------------------------------
	VGA_HS      <= horiz_sync_int;
	VGA_VS      <= vert_sync_int;
	VGA_R       <= vga_r_int;
	VGA_G       <= vga_g_int;
	VGA_B       <= vga_b_int;
	VGA_CLK     <= pixel_clock_int;
	VGA_BLANK_N <= video_on_int;
	VGA_SYNC_N  <= '0';

	U1 : VGA_SYNC_module
		PORT MAP(
			clock_50Mhz    => CLOCK_50,
			red            => red_int,
			green          => green_int,
			blue           => blue_int,
			red_out        => vga_r_int,
			green_out      => vga_g_int,
			blue_out       => vga_b_int,
			horiz_sync_out => horiz_sync_int,
			vert_sync_out  => vert_sync_int,
			video_on       => video_on_int,
			pixel_clock    => pixel_clock_int,
			pixel_row      => pixel_row_int,
			pixel_column   => pixel_column_int
		);

	-- -------------------------------------------------------------------------
	-- Tile renderer (game field)
	-- -------------------------------------------------------------------------
	U2 : tile_renderer
		PORT MAP(
			pixel_row    => pixel_row_int,
			pixel_column => pixel_column_int,
			notes_matrix => notes_matrix,
			hit_matrix   => hit_matrix,
			note_offset  => note_offset,
			Red          => tile_r,
			Green        => tile_g,
			Blue         => tile_b,
			video_on     => video_on_int
		);

	-- -------------------------------------------------------------------------
	-- Score/combo display overlay (always rendered but only shown in PLAYING)
	-- -------------------------------------------------------------------------
	vga_score_display_inst : ENTITY work.vga_score_display
		PORT MAP(
			pixel_row    => pixel_row_int,
			pixel_column => pixel_column_int,
			-- score
			score_ones      => score_ones,
			score_tens      => score_tens,
			score_hundreds  => score_hundreds,
			score_thousands => score_thousands,
			-- max score
			max_ones      => max_ones,
			max_tens      => max_tens,
			max_hundreds  => max_hundreds,
			max_thousands => max_thousands,
			-- combo
			combo_ones      => combo_ones,
			combo_tens      => combo_tens,
			combo_hundreds  => combo_hundreds,
			combo_thousands => combo_thousands,
			-- best combo
			best_combo_ones      => best_combo_ones,
			best_combo_tens      => best_combo_tens,
			best_combo_hundreds  => best_combo_hundreds,
			best_combo_thousands => best_combo_thousands,
			-- background from tile renderer
			red_in   => tile_r,
			green_in => tile_g,
			blue_in  => tile_b,
			-- overlaid output
			red_out   => score_display_r,
			green_out => score_display_g,
			blue_out  => score_display_b
		);

	-- -------------------------------------------------------------------------
	-- Menu renderer (splash screen)
	-- -------------------------------------------------------------------------
	menu_renderer_inst : ENTITY work.menu_renderer
		PORT MAP(
			pixel_row    => pixel_row_int,
			pixel_column => pixel_column_int,
			video_on     => video_on_int,
			blink_on     => blink_on,
			red_out      => menu_r,
			green_out    => menu_g,
			blue_out     => menu_b
		);

	-- -------------------------------------------------------------------------
	-- VGA output MUX: MENU shows splash screen, PLAYING shows game + score
	-- -------------------------------------------------------------------------
	red_int   <= menu_r          WHEN game_state = MENU ELSE score_display_r;
	green_int <= menu_g          WHEN game_state = MENU ELSE score_display_g;
	blue_int  <= menu_b          WHEN game_state = MENU ELSE score_display_b;

END structural;
