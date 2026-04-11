LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY score_to_bcd IS
	PORT (
		score : IN INTEGER;
		ones : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		tens : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		hundreds : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
		thousands : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF score_to_bcd IS
BEGIN
	PROCESS (score)
		VARIABLE temp : INTEGER;
	BEGIN
		temp := score MOD 10;
		ones <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 10) MOD 10;
		tens <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 100) MOD 10;
		hundreds <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));

		temp := (score / 1000) MOD 10;
		thousands <= STD_LOGIC_VECTOR(to_unsigned(temp, 4));
	END PROCESS;
END ARCHITECTURE;
