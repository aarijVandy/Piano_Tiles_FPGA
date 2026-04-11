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
		AUD_XCK : OUT STD_LOGIC -- Chip Clock

	);

END DE2_115_TOP;

ARCHITECTURE structural OF DE2_115_TOP IS

	-- Component declarations
	COMPONENT note_stage IS
		PORT (
			game_tick    : IN  STD_LOGIC;
			buttons      : IN  STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);
			notes_matrix : OUT note_matrix_t;
			score        : OUT INTEGER;
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
			note_offset  : IN  INTEGER RANGE 0 TO NOTE_HEIGHT;
			Red          : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			Green        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			Blue         : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			video_on     : IN  STD_LOGIC
		);
	END COMPONENT;

	-- Internal signals
	SIGNAL game_tick : STD_LOGIC;

	-- Debounced button signals
	SIGNAL buttons_debounced : STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- Note stage outputs
	SIGNAL notes_matrix : note_matrix_t;
	SIGNAL score : INTEGER;
	SIGNAL note_offset : INTEGER RANGE 0 TO NOTE_HEIGHT;

        -- VGA Signals
        SIGNAL red_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL green_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL blue_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_r_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_g_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL vga_b_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
        SIGNAL video_on_int : STD_LOGIC;
        SIGNAL vert_sync_int : STD_LOGIC;
        SIGNAL horiz_sync_int : STD_LOGIC;
        SIGNAL pixel_clock_int : STD_LOGIC;
        SIGNAL pixel_row_int : STD_LOGIC_VECTOR(10 DOWNTO 0);
        SIGNAL pixel_column_int : STD_LOGIC_VECTOR(10 DOWNTO 0);

	-- Score display signals (convert to BCD)
	SIGNAL score_ones : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_tens : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_hundreds : STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL score_thousands : STD_LOGIC_VECTOR(3 DOWNTO 0);

BEGIN

	-- Use vertical sync as the game tick so game logic updates once per frame,
	-- during blanking, in lock-step with the display (eliminates tearing/jitter)
	game_tick <= vert_sync_int;

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

	note_stage_inst : note_stage
		PORT MAP(
			game_tick    => game_tick,
			buttons      => buttons_debounced,
			notes_matrix => notes_matrix,
			score        => score,
			note_offset  => note_offset
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
	bcd7seg_ones : bcd7seg
		PORT MAP(
			bcd => score_ones,
			seg => HEX0
		);

	bcd7seg_tens : bcd7seg
		PORT MAP(
			bcd => score_tens,
			seg => HEX1
		);

	bcd7seg_hundreds : bcd7seg
		PORT MAP(
			bcd => score_hundreds,
			seg => HEX2
		);

	bcd7seg_thousands : bcd7seg
		PORT MAP(
			bcd => score_thousands,
			seg => HEX3
		);

	HEX4 <= (OTHERS => '1'); -- Turn off
	HEX5 <= (OTHERS => '1'); -- Turn off
	HEX6 <= (OTHERS => '1'); -- Turn off
	HEX7 <= (OTHERS => '1'); -- Turn off
	LEDR <= (OTHERS => '0'); -- Unused

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

	-- VGA Logic
	VGA_HS <= horiz_sync_int;
	VGA_VS <= vert_sync_int;
	VGA_R <= vga_r_int;
	VGA_G <= vga_g_int;
	VGA_B <= vga_b_int;
	VGA_CLK <= pixel_clock_int;
	VGA_BLANK_N <= video_on_int;

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

	U2 : tile_renderer
		PORT MAP(
			pixel_row    => pixel_row_int,
			pixel_column => pixel_column_int,
			notes_matrix => notes_matrix,
			note_offset  => note_offset,
			Red          => red_int,
			Green        => green_int,
			Blue         => blue_int,
			video_on     => video_on_int
		);

END structural;
