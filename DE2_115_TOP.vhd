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
	GENERIC (
		TICKS_PER_SECOND : NATURAL := 50_000_000 -- default for 50 MHz CLOCK_50
	);
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
		AUD_XCK : OUT STD_LOGIC -- Chip Clock

	);

END DE2_115_TOP;

ARCHITECTURE structural OF DE2_115_TOP IS

	-- Game timing configuration
	CONSTANT GAME_TICK_RATE : NATURAL := 160;
	-- Clock divider constants
	CONSTANT CLOCK_DIVIDER : NATURAL := TICKS_PER_SECOND / GAME_TICK_RATE; -- 50,000,000 / 160 = 312,500

	-- Internal signals
	SIGNAL game_tick : STD_LOGIC := '0';
	SIGNAL game_tick_counter : NATURAL RANGE 0 TO CLOCK_DIVIDER - 1 := 0;

	-- Debounced button signals
	SIGNAL buttons_debounced : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Note stage outputs
	SIGNAL notes_matrix : note_matrix_t;
	SIGNAL score : INTEGER;
	SIGNAL note_offset : INTEGER RANGE 0 TO NOTE_HEIGHT;

	-- Score display signals (convert to BCD)
	SIGNAL score_ones : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_tens : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_hundreds : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_thousands : STD_LOGIC_VECTOR(3 DOWNTO 0);

BEGIN

	-- Generate a game tick at the specified GAME_TICK_RATE (e.g., 160 BPM)
	PROCESS (CLOCK_50)
	BEGIN
		IF rising_edge(CLOCK_50) THEN
			IF game_tick_counter = CLOCK_DIVIDER - 1 THEN
				game_tick <= '1';
				game_tick_counter <= 0;
			ELSE
				game_tick <= '0';
				game_tick_counter <= game_tick_counter + 1;
			END IF;
		END IF;
	END PROCESS;

	buttons_debounced(0) <= '1' WHEN KEY(0) = '0' ELSE
	'0'; -- Active-low buttons
	buttons_debounced(1) <= '1' WHEN KEY(1) = '0' ELSE
	'0';
	buttons_debounced(2) <= '1' WHEN KEY(2) = '0' ELSE
	'0';
	buttons_debounced(3) <= '1' WHEN KEY(3) = '0' ELSE
	'0';

	-- debounce0 : ENTITY work.key_debounce
	--     GENERIC MAP(TICKS_PER_SECOND => TICKS_PER_SECOND)
	--     PORT MAP(
	--         clk => CLOCK_50,
	--         key => KEY(0),
	--         out_signal => buttons_debounced(0)
	--     );

	-- debounce1 : ENTITY work.key_debounce
	--     GENERIC MAP(TICKS_PER_SECOND => TICKS_PER_SECOND)
	--     PORT MAP(
	--         clk => CLOCK_50,
	--         key => KEY(1),
	--         out_signal => buttons_debounced(1)
	--     );

	-- debounce2 : ENTITY work.key_debounce
	--     GENERIC MAP(TICKS_PER_SECOND => TICKS_PER_SECOND)
	--     PORT MAP(
	--         clk => CLOCK_50,
	--         key => KEY(2),
	--         out_signal => buttons_debounced(2)
	--     );

	-- debounce3 : ENTITY work.key_debounce
	--     GENERIC MAP(TICKS_PER_SECOND => TICKS_PER_SECOND)
	--     PORT MAP(
	--         clk => CLOCK_50,
	--         key => KEY(3),
	--         out_signal => buttons_debounced(3)
	--     );

	note_stage_inst : ENTITY work.note_stage
		PORT MAP(
			game_tick => game_tick,
			buttons => buttons_debounced,
			notes_matrix => notes_matrix,
			score => score,
			note_offset => note_offset
		);

	--  MAP NOTES TO LEDS
	LEDG(0) <= notes_matrix(0)(NOTE_COUNT - 1);
	LEDG(1) <= notes_matrix(1)(NOTE_COUNT - 1);
	LEDG(2) <= notes_matrix(2)(NOTE_COUNT - 1);
	LEDG(3) <= notes_matrix(3)(NOTE_COUNT - 1);
	LEDG(8 DOWNTO 4) <= (OTHERS => '0'); -- Unused

	-- SCORE TO BCD CONVERSION

	-- Convert integer score to BCD digits
	PROCESS (score)
		VARIABLE temp : INTEGER;
	BEGIN
		temp := score MOD 10;
		score_ones <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 10) MOD 10;
		score_tens <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 100) MOD 10;
		score_hundreds <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 1000) MOD 10;
		score_thousands <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));
	END PROCESS;

	-- BCD TO 7-SEGMENT DECODERS
	bcd7seg_ones : ENTITY work.bcd7seg
		PORT MAP(
			bcd => score_ones,
			seg => HEX0
		);

	bcd7seg_tens : ENTITY work.bcd7seg
		PORT MAP(
			bcd => score_tens,
			seg => HEX1
		);

	bcd7seg_hundreds : ENTITY work.bcd7seg
		PORT MAP(
			bcd => score_hundreds,
			seg => HEX2
		);

	bcd7seg_thousands : ENTITY work.bcd7seg
		PORT MAP(
			bcd => score_thousands,
			seg => HEX3
		);

	HEX4 <= (OTHERS => '0'); -- Turn off
	HEX5 <= (OTHERS => '1'); -- Turn off
	HEX6 <= (OTHERS => '1'); -- Turn off
	HEX7 <= (OTHERS => '1'); -- Turn off
	LEDR <= (OTHERS => '1'); -- Unused

	-- Other board outputs (tie off if not used)
	UART_TXD <= '0';
	UART_CTS <= '1';
	SMA_CLKOUT <= '0';
	LCD_ON <= '0';
	LCD_BLON <= '0';
	LCD_EN <= '0';
	LCD_RS <= '0';
	LCD_RW <= '1';
	AUD_XCK <= '0';

END structural;

-- Architecture body
-- 		Describes the functionality or internal implementation of the entity

-- ARCHITECTURE structural OF DE2_115_TOP IS

-- 	COMPONENT VGA_SYNC_module

-- 		PORT (
-- 			clock_50Mhz : IN STD_LOGIC;
-- 			red, green, blue : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 			red_out, green_out, blue_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 			horiz_sync_out, vert_sync_out, video_on, pixel_clock : OUT STD_LOGIC;
-- 			pixel_row, pixel_column : OUT STD_LOGIC_VECTOR(10 DOWNTO 0));

-- 	END COMPONENT;

-- 	COMPONENT ball

-- 		PORT (
-- 			pixel_row, pixel_column : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
-- 			Red, Green, Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 			Vert_sync : IN STD_LOGIC);
-- 	END COMPONENT;

-- 	SIGNAL red_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL green_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL blue_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL vga_r_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL vga_g_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL vga_b_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
-- 	SIGNAL video_on_int : STD_LOGIC;
-- 	SIGNAL vert_sync_int : STD_LOGIC;
-- 	SIGNAL horiz_sync_int : STD_LOGIC;
-- 	SIGNAL pixel_clock_int : STD_LOGIC;
-- 	SIGNAL pixel_row_int : STD_LOGIC_VECTOR(10 DOWNTO 0);
-- 	SIGNAL pixel_column_int : STD_LOGIC_VECTOR(10 DOWNTO 0);
-- BEGIN

-- 	VGA_HS <= horiz_sync_int;
-- 	VGA_VS <= vert_sync_int;
-- 	VGA_R <= vga_r_int;
-- 	VGA_G <= vga_g_int;
-- 	VGA_B <= vga_b_int;

-- 	U1 : VGA_SYNC_module PORT MAP
-- 	(
-- 		clock_50Mhz => CLOCK_50,
-- 		red => red_int,
-- 		green => green_int,
-- 		blue => blue_int,
-- 		red_out => vga_r_int,
-- 		green_out => vga_g_int,
-- 		blue_out => vga_b_int,
-- 		horiz_sync_out => horiz_sync_int,
-- 		vert_sync_out => vert_sync_int,
-- 		video_on => VGA_BLANK_N,
-- 		pixel_clock => VGA_CLK,
-- 		pixel_row => pixel_row_int,
-- 		pixel_column => pixel_column_int
-- 	);

-- 	U2 : ball PORT MAP
-- 	(
-- 		pixel_row => pixel_row_int,
-- 		pixel_column => pixel_column_int,
-- 		Red => red_int,
-- 		Green => green_int,
-- 		Blue => blue_int,
-- 		Vert_sync => vert_sync_int
-- 	);
-- END structural;