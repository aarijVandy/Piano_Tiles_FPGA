-- =============================================================================
-- WM8731 I2C Configuration Controller
-- Writes the necessary registers to set up the codec for I2S DAC output
-- at 48 kHz, 16-bit, slave mode.
--
-- Target: DE2-115 (Altera Cyclone IV)
-- I2C device address: 0x34 (0x1A with R/W bit = 0)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_i2c_config is
    port (
        clk       : in    std_logic;   -- 50 MHz system clock
        reset_n   : in    std_logic;   -- Active-low reset
        i2c_sclk  : out   std_logic;   -- I2C clock (directly driven)
        i2c_sdat  : inout std_logic;   -- I2C data (active-low / tristate)
        done      : out   std_logic    -- High when all registers written
    );
end entity audio_i2c_config;

architecture rtl of audio_i2c_config is

    -- I2C clock divider: 50 MHz / 500 = 100 kHz I2C clock
    -- We use 4 phases per I2C bit period, so tick at 400 kHz: 50M / 125 = 400 kHz
    constant CLK_DIV : integer := 125;

    -- WM8731 I2C address (7-bit: 0x1A, with write bit: 0x34)
    constant DEV_ADDR : std_logic_vector(7 downto 0) := x"34";

    -- Register configuration data: 16 bits each = reg_addr(6:0) & data(8:0)
    type reg_data_array is array (natural range <>) of std_logic_vector(15 downto 0);
    constant NUM_REGS : integer := 10;
    constant REG_DATA : reg_data_array(0 to NUM_REGS - 1) := (
        -- Reg 0x0F: Reset
        "0001111" & "000000000",
        -- Reg 0x02: Left headphone out, 0 dB
        "0000010" & "001111001",
        -- Reg 0x03: Right headphone out, 0 dB
        "0000011" & "001111001",
        -- Reg 0x04: Analog audio path - select DAC
        "0000100" & "000010000",
        -- Reg 0x05: Digital audio path - no de-emphasis
        "0000101" & "000000000",
        -- Reg 0x06: Power down - all on (line in, mic, ADC powered down)
        "0000110" & "000000111",
        -- Reg 0x07: Digital audio interface - I2S, 16-bit, slave
        "0000111" & "000000010",
        -- Reg 0x08: Sampling control - normal mode, 256fs, 48 kHz
        "0001000" & "000000000",
        -- Reg 0x09: Active control - activate
        "0001001" & "000000001",
        -- Reg 0x02: Left headphone out again (ensure volume set after activate)
        "0000010" & "001111001"
    );

    -- State machine
    type state_t is (
        ST_IDLE,
        ST_START,
        ST_SEND_BIT,
        ST_ACK,
        ST_STOP,
        ST_PAUSE,
        ST_DONE
    );
    signal state      : state_t := ST_IDLE;

    -- Clock divider
    signal clk_count  : integer range 0 to CLK_DIV - 1 := 0;
    signal clk_tick   : std_logic := '0';
    signal phase      : unsigned(1 downto 0) := "00";

    -- I2C signals (directly driven internally)
    signal sclk_reg   : std_logic := '1';
    signal sda_out    : std_logic := '1';
    signal sda_oe     : std_logic := '1';  -- '1' = drive SDA, '0' = release (for ACK)

    -- Data tracking
    signal reg_index  : integer range 0 to NUM_REGS := 0;
    signal byte_index : integer range 0 to 2 := 0;    -- 0=addr, 1=data_hi, 2=data_lo
    signal bit_index  : integer range 0 to 7 := 7;    -- MSB first
    signal tx_byte    : std_logic_vector(7 downto 0) := (others => '0');

    -- Startup delay counter (allow codec to power up)
    signal delay_cnt  : unsigned(19 downto 0) := (others => '0');
    signal delay_done : std_logic := '0';

    -- Pause counter between register writes
    signal pause_cnt  : unsigned(15 downto 0) := (others => '0');

begin

    -- Directly drove I2C clock; SDA is open-drain (active low, tristate high)
    i2c_sclk <= sclk_reg;
    i2c_sdat <= '0' when (sda_oe = '1' and sda_out = '0') else 'Z';

    done <= '1' when state = ST_DONE else '0';

    -- Clock divider: generates a tick at 4x I2C frequency
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            clk_count <= 0;
            clk_tick  <= '0';
        elsif rising_edge(clk) then
            clk_tick <= '0';
            if clk_count = CLK_DIV - 1 then
                clk_count <= 0;
                clk_tick  <= '1';
            else
                clk_count <= clk_count + 1;
            end if;
        end if;
    end process;

    -- Startup delay: ~20 ms after reset (1M cycles at 50 MHz)
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            delay_cnt  <= (others => '0');
            delay_done <= '0';
        elsif rising_edge(clk) then
            if delay_done = '0' then
                delay_cnt <= delay_cnt + 1;
                if delay_cnt = to_unsigned(999999, 20) then
                    delay_done <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Main I2C state machine
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state      <= ST_IDLE;
            sclk_reg   <= '1';
            sda_out    <= '1';
            sda_oe     <= '1';
            reg_index  <= 0;
            byte_index <= 0;
            bit_index  <= 7;
            tx_byte    <= (others => '0');
            phase      <= "00";
            pause_cnt  <= (others => '0');
        elsif rising_edge(clk) then
            if clk_tick = '1' then
                case state is

                    -- Wait for startup delay
                    when ST_IDLE =>
                        sclk_reg <= '1';
                        sda_out  <= '1';
                        sda_oe   <= '1';
                        if delay_done = '1' then
                            if reg_index < NUM_REGS then
                                state <= ST_START;
                                phase <= "00";
                            else
                                state <= ST_DONE;
                            end if;
                        end if;

                    -- Generate START condition: SDA falls while SCL is high
                    when ST_START =>
                        case phase is
                            when "00" =>
                                sclk_reg <= '1';
                                sda_out  <= '1';
                                sda_oe   <= '1';
                                phase    <= "01";
                            when "01" =>
                                sda_out <= '0';    -- SDA goes low while SCL high
                                phase   <= "10";
                            when "10" =>
                                sclk_reg <= '0';   -- SCL goes low
                                phase    <= "11";
                            when "11" =>
                                -- Load first byte (device address)
                                tx_byte    <= DEV_ADDR;
                                byte_index <= 0;
                                bit_index  <= 7;
                                state      <= ST_SEND_BIT;
                                phase      <= "00";
                            when others =>
                                phase <= "00";
                        end case;

                    -- Send one bit of tx_byte
                    when ST_SEND_BIT =>
                        case phase is
                            when "00" =>
                                -- Set SDA while SCL is low
                                sda_out <= tx_byte(bit_index);
                                sda_oe  <= '1';
                                phase   <= "01";
                            when "01" =>
                                sclk_reg <= '1';   -- Raise SCL
                                phase    <= "10";
                            when "10" =>
                                phase <= "11";      -- Hold SCL high
                            when "11" =>
                                sclk_reg <= '0';    -- Lower SCL
                                if bit_index = 0 then
                                    -- Byte complete, go to ACK
                                    state <= ST_ACK;
                                else
                                    bit_index <= bit_index - 1;
                                end if;
                                phase <= "00";
                            when others =>
                                phase <= "00";
                        end case;

                    -- ACK cycle: release SDA, clock SCL, then check next byte
                    when ST_ACK =>
                        case phase is
                            when "00" =>
                                sda_oe <= '0';      -- Release SDA for ACK
                                phase  <= "01";
                            when "01" =>
                                sclk_reg <= '1';    -- SCL high
                                phase    <= "10";
                            when "10" =>
                                phase <= "11";       -- Hold (ACK is read here, we ignore it)
                            when "11" =>
                                sclk_reg <= '0';
                                sda_oe   <= '1';
                                sda_out  <= '0';

                                -- Determine next action
                                if byte_index = 2 then
                                    -- All 3 bytes sent, go to STOP
                                    state <= ST_STOP;
                                else
                                    -- Load next byte
                                    byte_index <= byte_index + 1;
                                    bit_index  <= 7;
                                    if byte_index = 0 then
                                        -- Next: high byte of register data
                                        tx_byte <= REG_DATA(reg_index)(15 downto 8);
                                    else
                                        -- Next: low byte of register data
                                        tx_byte <= REG_DATA(reg_index)(7 downto 0);
                                    end if;
                                    state <= ST_SEND_BIT;
                                end if;
                                phase <= "00";
                            when others =>
                                phase <= "00";
                        end case;

                    -- Generate STOP condition: SDA rises while SCL is high
                    when ST_STOP =>
                        case phase is
                            when "00" =>
                                sda_out <= '0';
                                sda_oe  <= '1';
                                phase   <= "01";
                            when "01" =>
                                sclk_reg <= '1';    -- SCL high
                                phase    <= "10";
                            when "10" =>
                                sda_out <= '1';     -- SDA rises while SCL high = STOP
                                phase   <= "11";
                            when "11" =>
                                reg_index <= reg_index + 1;
                                pause_cnt <= (others => '0');
                                state     <= ST_PAUSE;
                                phase     <= "00";
                            when others =>
                                phase <= "00";
                        end case;

                    -- Brief pause between register writes
                    when ST_PAUSE =>
                        pause_cnt <= pause_cnt + 1;
                        if pause_cnt = to_unsigned(200, 16) then
                            state <= ST_IDLE;
                        end if;

                    when ST_DONE =>
                        sclk_reg <= '1';
                        sda_out  <= '1';
                        sda_oe   <= '1';

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
