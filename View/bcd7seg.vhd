LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
ENTITY bcd7seg IS
	PORT (
		bcd : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		seg : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF bcd7seg IS
BEGIN
	PROCESS (bcd)
	BEGIN
		CASE bcd IS
			WHEN "0000" => seg <= "1000000"; -- 0
			WHEN "0001" => seg <= "1111001"; -- 1
			WHEN "0010" => seg <= "0100100"; -- 2
			WHEN "0011" => seg <= "0110000"; -- 3
			WHEN "0100" => seg <= "0011001"; -- 4
			WHEN "0101" => seg <= "0010010"; -- 5
			WHEN "0110" => seg <= "0000010"; -- 6
			WHEN "0111" => seg <= "1111000"; -- 7
			WHEN "1000" => seg <= "0000000"; -- 8
			WHEN "1001" => seg <= "0010000"; -- 9
			WHEN OTHERS => seg <= "0111111"; -- blank / invalid
		END CASE;
	END PROCESS;
END ARCHITECTURE;