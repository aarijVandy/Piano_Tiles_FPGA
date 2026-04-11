library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- using a linear feedback shift register to create a random 32-bit value
entity randomizer is
    Port (
        clk      : in  STD_LOGIC;
        reset    : in  STD_LOGIC;
        enable   : in  STD_LOGIC;
        rand_out : out STD_LOGIC_VECTOR(31 downto 0)
    );
end randomizer;

architecture Behavioral of randomizer is
    signal lfsr : STD_LOGIC_VECTOR(31 downto 0) := x"DEADBEEF";  -- non-zero seed
begin
    process(clk, reset)
        variable feedback : STD_LOGIC;
    begin
        if reset = '1' then
            lfsr <= x"DEADBEEF";  -- reset seed
        elsif rising_edge(clk) then
            if enable = '1' then
                -- 32-bit LFSR with taps at bits 31, 21, 1, 0 (maximal length)
                feedback := lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0);
                lfsr <= lfsr(30 downto 0) & feedback;
            end if;
        end if;
    end process;

    rand_out <= lfsr;
end Behavioral;