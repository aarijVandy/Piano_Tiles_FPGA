LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY font_rom IS
	PORT (
		digit : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- value 0-9
		row   : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- 0-7 y pixel
		col   : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- 0-7 x pixel
		pixel : OUT STD_LOGIC
	);
END ENTITY;

ARCHITECTURE rtl OF font_rom IS
	-- 10 characters (digits 0-9), each is 8 rows, each row is 8 bits (STD_LOGIC_VECTOR)
	TYPE font_array IS ARRAY (0 TO 9, 0 TO 7) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	
	-- A simple 5x7-like font, stored in an 8x8 grid (padded on the right/bottom)
	CONSTANT digit_rom : font_array := (
		-- 0
		0 => (
			"00111000",
			"01000100",
			"01000100",
			"01000100",
			"01000100",
			"01000100",
			"00111000",
			"00000000"
		),
		-- 1
		1 => (
			"00010000",
			"00110000",
			"00010000",
			"00010000",
			"00010000",
			"00010000",
			"00111000",
			"00000000"
		),
		-- 2
		2 => (
			"00111000",
			"01000100",
			"00000100",
			"00001000",
			"00010000",
			"00100000",
			"01111100",
			"00000000"
		),
		-- 3
		3 => (
			"00111000",
			"01000100",
			"00000100",
			"00011000",
			"00000100",
			"01000100",
			"00111000",
			"00000000"
		),
		-- 4
		4 => (
			"00001000",
			"00011000",
			"00101000",
			"01001000",
			"01111100",
			"00001000",
			"00001000",
			"00000000"
		),
		-- 5
		5 => (
			"01111100",
			"01000000",
			"01111000",
			"00000100",
			"00000100",
			"01000100",
			"00111000",
			"00000000"
		),
		-- 6
		6 => (
			"00111000",
			"01000100",
			"01000000",
			"01111000",
			"01000100",
			"01000100",
			"00111000",
			"00000000"
		),
		-- 7
		7 => (
			"01111100",
			"00000100",
			"00001000",
			"00010000",
			"00100000",
			"00100000",
			"00100000",
			"00000000"
		),
		-- 8
		8 => (
			"00111000",
			"01000100",
			"01000100",
			"00111000",
			"01000100",
			"01000100",
			"00111000",
			"00000000"
		),
		-- 9
		9 => (
			"00111000",
			"01000100",
			"01000100",
			"00111100",
			"00000100",
			"01000100",
			"00111000",
			"00000000"
		)
	);

BEGIN
	PROCESS (digit, row, col)
		VARIABLE d_idx : INTEGER RANGE 0 TO 15;
		VARIABLE r_idx : INTEGER RANGE 0 TO 7;
		VARIABLE c_idx : INTEGER RANGE 0 TO 7;
	BEGIN
		d_idx := to_integer(unsigned(digit));
		r_idx := to_integer(unsigned(row));
		c_idx := to_integer(unsigned(col));

		IF d_idx >= 0 AND d_idx <= 9 THEN
			-- VHDL arrays of std_logic_vector are accessed with (array_index)(vector_index)
			-- our vector is 7 DOWNTO 0, meaning index 7 is the leftmost bit. 
			-- So if c_idx=0 (first column), we want bit 7.
			pixel <= digit_rom(d_idx, r_idx)(7 - c_idx);
		ELSE
			pixel <= '0';
		END IF;
	END PROCESS;
END ARCHITECTURE;
