library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- using a linear feedback shift register to create a random 0-3 values

entity randomizer is
    Port (
        clk      : in  STD_LOGIC;
        reset    : in  STD_LOGIC;
        enable   : in  STD_LOGIC;                     -- advance random value when high
        rand_out : out STD_LOGIC_VECTOR(1 downto 0)  -- values 00 to 11 = 0 to 3
    );
    end randomizer;

architecture Behavioral of randomizer is
    signal lfsr : STD_LOGIC_VECTOR(3 downto 0) := "1011";  -- non-zero seed
begin
    process(clk, reset)
            variable feedback : STD_LOGIC;
        begin
            if reset = '1' then
                lfsr <= "1011";  -- reset seed
            elsif rising_edge(clk) then
                if enable = '1' then
                    -- 4-bit LFSR with taps at bit3 and bit2
                    feedback := lfsr(3) xor lfsr(2);
                    lfsr <= lfsr(2 downto 0) & feedback; -- take last 2 digits
                end if;
            end if;
        end process;

        rand_out <= lfsr(1 downto 0);

    end Behavioral;