-- audio_i2c_config.vhd
--
-- Writes the WM8731 codec's control registers over I2C at startup so the
-- DAC path comes up alive and unmuted before any samples are streamed.
--
-- WM8731 lives on the DE2-115 audio I2C bus at 7-bit address 0x1A.
-- Each "write" is: START | addr<<1|W | {reg[6:0], data[8]} | data[7:0] | STOP
-- (the WM8731 packs a 7-bit register address and a 9-bit data word into two
--  I2C data bytes, MSB first).
--
-- Clocked from CLOCK_50 so it runs independently of the audio MCLK path.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_i2c_config is
    port (
        clk_50     : in    std_logic;            -- CLOCK_50
        reset      : in    std_logic;            -- active-high sync reset
        i2c_sclk   : out   std_logic;            -- to I2C_SCLK pad
        i2c_sdat   : inout std_logic;            -- to I2C_SDAT pad (open-drain)
        done       : out   std_logic             -- '1' once all regs written
    );
end audio_i2c_config;

architecture rtl of audio_i2c_config is

    -- 4 phases per I2C bit. 50 MHz / 125 = 400 kHz -> ~100 kHz SCL.
    constant PHASE_DIV : integer := 125;

    -- WM8731 device address (7 bits)
    constant DEV_ADDR  : std_logic_vector(6 downto 0) := "0011010"; -- 0x1A

    type reg_rec is record
        a : std_logic_vector(6 downto 0);
        d : std_logic_vector(8 downto 0);
    end record;
    type reg_array is array (natural range <>) of reg_rec;

    -- 10-register init sequence. Reset, then powered / routed / activated.
    constant REGS : reg_array := (
        0 => (a => "0001111", d => "000000000"), -- 0x0F software reset
        1 => (a => "0000110", d => "000010111"), -- 0x06 power down (DAC on)
        2 => (a => "0000100", d => "000010000"), -- 0x04 analog path: DAC select
        3 => (a => "0000101", d => "000000000"), -- 0x05 digital path: un-mute
        4 => (a => "0000111", d => "000000010"), -- 0x07 I2S, 16-bit, slave
        5 => (a => "0001000", d => "000000000"), -- 0x08 256 fs / 48 kHz nominal
        6 => (a => "0000010", d => "001111001"), -- 0x02 LHP 0 dB
        7 => (a => "0000011", d => "001111001"), -- 0x03 RHP 0 dB
        8 => (a => "0001001", d => "000000001"), -- 0x09 activate interface
        9 => (a => "0000110", d => "000000010")  -- 0x06 final: OUTPD = 0
    );
    constant REG_COUNT : integer := 10;

    type state_t is (ST_WAIT_POR, ST_START, ST_SEND, ST_STOP, ST_NEXT, ST_DONE);
    signal state : state_t := ST_WAIT_POR;

    -- ~20 ms POR wait: 50e6 * 0.02 = 1e6 cycles.
    constant POR_CYCLES : integer := 1_000_000;
    signal por_cnt      : integer range 0 to POR_CYCLES := 0;

    signal phase_cnt : integer range 0 to PHASE_DIV-1 := 0;
    signal phase     : integer range 0 to 3 := 0;

    signal reg_idx   : integer range 0 to REG_COUNT := 0;

    -- 27 bit positions per transfer: 3 bytes * (8 data + 1 ACK)
    signal bit_idx   : integer range 0 to 26 := 0;

    signal sclk_r    : std_logic := '1';
    signal sdat_r    : std_logic := '1';

    function byte0(dev : std_logic_vector(6 downto 0)) return std_logic_vector is
    begin
        return dev & '0';  -- R/W = 0 (write)
    end function;

    function byte1(r : reg_rec) return std_logic_vector is
    begin
        return r.a & r.d(8);
    end function;

    function byte2(r : reg_rec) return std_logic_vector is
    begin
        return r.d(7 downto 0);
    end function;

begin

    i2c_sclk <= sclk_r;
    -- Open-drain: drive '0', otherwise release to high-Z and let pull-up win.
    i2c_sdat <= '0' when sdat_r = '0' else 'Z';

    done <= '1' when state = ST_DONE else '0';

    process (clk_50)
        variable cur_byte : std_logic_vector(7 downto 0);
        variable byte_sel : integer range 0 to 2;
        variable bit_in_byte : integer range 0 to 8;
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                state     <= ST_WAIT_POR;
                por_cnt   <= 0;
                phase_cnt <= 0;
                phase     <= 0;
                reg_idx   <= 0;
                bit_idx   <= 0;
                sclk_r    <= '1';
                sdat_r    <= '1';

            elsif state = ST_WAIT_POR then
                -- Count every clock, not every phase tick, so 20 ms is accurate.
                sclk_r <= '1';
                sdat_r <= '1';
                if por_cnt = POR_CYCLES-1 then
                    state <= ST_START;
                    phase <= 0;
                    phase_cnt <= 0;
                else
                    por_cnt <= por_cnt + 1;
                end if;

            elsif phase_cnt = PHASE_DIV-1 then
                phase_cnt <= 0;

                case state is

                    when ST_WAIT_POR =>
                        null;  -- handled above

                    when ST_START =>
                        case phase is
                            when 0 => sclk_r <= '1'; sdat_r <= '1';
                            when 1 => sclk_r <= '1'; sdat_r <= '0';
                            when 2 => sclk_r <= '0'; sdat_r <= '0';
                            when 3 => state <= ST_SEND; bit_idx <= 0;
                        end case;
                        if phase = 3 then phase <= 0;
                        else phase <= phase + 1;
                        end if;

                    when ST_SEND =>
                        byte_sel    := bit_idx / 9;
                        bit_in_byte := bit_idx mod 9;
                        case byte_sel is
                            when 0 => cur_byte := byte0(DEV_ADDR);
                            when 1 => cur_byte := byte1(REGS(reg_idx));
                            when 2 => cur_byte := byte2(REGS(reg_idx));
                        end case;

                        case phase is
                            when 0 =>
                                sclk_r <= '0';
                                if bit_in_byte = 8 then
                                    sdat_r <= '1';  -- release SDA for ACK
                                else
                                    sdat_r <= cur_byte(7 - bit_in_byte);
                                end if;
                            when 1 => sclk_r <= '1';
                            when 2 => sclk_r <= '1';
                            when 3 =>
                                sclk_r <= '0';
                                if bit_idx = 26 then
                                    state <= ST_STOP;
                                else
                                    bit_idx <= bit_idx + 1;
                                end if;
                        end case;
                        if phase = 3 then phase <= 0;
                        else phase <= phase + 1;
                        end if;

                    when ST_STOP =>
                        case phase is
                            when 0 => sclk_r <= '0'; sdat_r <= '0';
                            when 1 => sclk_r <= '1'; sdat_r <= '0';
                            when 2 => sclk_r <= '1'; sdat_r <= '1';
                            when 3 => state <= ST_NEXT;
                        end case;
                        if phase = 3 then phase <= 0;
                        else phase <= phase + 1;
                        end if;

                    when ST_NEXT =>
                        if reg_idx = REG_COUNT-1 then
                            state <= ST_DONE;
                        else
                            reg_idx <= reg_idx + 1;
                            state   <= ST_START;
                            phase   <= 0;
                        end if;

                    when ST_DONE =>
                        sclk_r <= '1';
                        sdat_r <= '1';

                end case;

            else
                phase_cnt <= phase_cnt + 1;
            end if;
        end if;
    end process;

end rtl;
