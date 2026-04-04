-- =============================================================================
-- MIDI Sequencer
--
-- Reads preprocessed events from the MIDI ROM and outputs note on/off
-- commands with correct timing.  The ROM contains fixed-width 5-byte
-- records produced by convert_midi.py:
--
--   [0-2] delta time in 48 kHz sample periods (24-bit big-endian)
--   [3]   command: 0x01 = note on, 0x00 = note off, 0xFF = end of song
--   [4]   MIDI note number (0-127)
--
-- The sequencer uses sample_tick (48 kHz pulse) as its time base.
--
-- Target: DE2-115 (Altera Cyclone IV)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity midi_sequencer is
    generic (
        ROM_ADDR_BITS : integer := 16   -- address width of the MIDI ROM
    );
    port (
        clk          : in  std_logic;   -- system clock (MCLK, 12.288 MHz)
        reset_n      : in  std_logic;
        start        : in  std_logic;   -- pulse to begin playback
        sample_tick  : in  std_logic;   -- pulse at 48 kHz (from I2S sample_req)

        -- ROM interface
        rom_addr     : out std_logic_vector(ROM_ADDR_BITS - 1 downto 0);
        rom_data     : in  std_logic_vector(7 downto 0);

        -- Event output (active for one clock cycle)
        evt_valid    : out std_logic;
        evt_note_on  : out std_logic;   -- '1' = note on, '0' = note off
        evt_note     : out std_logic_vector(6 downto 0);

        -- Status
        playing      : out std_logic
    );
end entity midi_sequencer;

architecture rtl of midi_sequencer is

    -- State machine
    type state_t is (
        ST_IDLE,         -- waiting for start pulse
        ST_READ_DT0,    -- set address for delta byte 0
        ST_LATCH_DT0,   -- latch delta byte 0 (MSB), set addr for byte 1
        ST_LATCH_DT1,   -- latch delta byte 1, set addr for byte 2
        ST_LATCH_DT2,   -- latch delta byte 2 (LSB), set addr for command
        ST_LATCH_CMD,   -- latch command, set addr for note
        ST_LATCH_NOTE,  -- latch note, check command
        ST_WAIT,        -- count down delta time using sample ticks
        ST_EXECUTE,     -- fire the event
        ST_DONE          -- end of song
    );
    signal state : state_t := ST_IDLE;

    -- Current position in ROM (byte offset)
    signal rom_ptr : unsigned(ROM_ADDR_BITS - 1 downto 0) := (others => '0');

    -- Event fields being read
    signal delta_time : unsigned(23 downto 0) := (others => '0');
    signal command    : std_logic_vector(7 downto 0) := (others => '0');
    signal note       : std_logic_vector(6 downto 0) := (others => '0');

    -- Countdown timer
    signal tick_count : unsigned(23 downto 0) := (others => '0');

begin

    rom_addr <= std_logic_vector(rom_ptr);

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state     <= ST_IDLE;
            rom_ptr   <= (others => '0');
            delta_time<= (others => '0');
            command   <= (others => '0');
            note      <= (others => '0');
            tick_count<= (others => '0');
            evt_valid <= '0';
            evt_note_on <= '0';
            evt_note  <= (others => '0');
            playing   <= '0';

        elsif rising_edge(clk) then

            -- Default: event output is a single-cycle pulse
            evt_valid <= '0';

            case state is

                when ST_IDLE =>
                    playing <= '0';
                    if start = '1' then
                        rom_ptr <= (others => '0');
                        state   <= ST_READ_DT0;
                        playing <= '1';
                    end if;

                -- 5-byte read pipeline (ROM has 1-cycle latency)
                -- We set the address in one state and latch data in the next.

                when ST_READ_DT0 =>
                    -- Address already set to rom_ptr (= byte 0 of record)
                    -- Advance address for next byte
                    rom_ptr <= rom_ptr + 1;
                    state   <= ST_LATCH_DT0;

                when ST_LATCH_DT0 =>
                    delta_time(23 downto 16) <= unsigned(rom_data);
                    rom_ptr <= rom_ptr + 1;
                    state   <= ST_LATCH_DT1;

                when ST_LATCH_DT1 =>
                    delta_time(15 downto 8) <= unsigned(rom_data);
                    rom_ptr <= rom_ptr + 1;
                    state   <= ST_LATCH_DT2;

                when ST_LATCH_DT2 =>
                    delta_time(7 downto 0) <= unsigned(rom_data);
                    rom_ptr <= rom_ptr + 1;
                    state   <= ST_LATCH_CMD;

                when ST_LATCH_CMD =>
                    command <= rom_data;
                    rom_ptr <= rom_ptr + 1;
                    state   <= ST_LATCH_NOTE;

                when ST_LATCH_NOTE =>
                    note <= rom_data(6 downto 0);

                    -- Check for end-of-song
                    if command = x"FF" then
                        state <= ST_DONE;
                    elsif delta_time = 0 then
                        -- No wait needed, execute immediately
                        state <= ST_EXECUTE;
                    else
                        tick_count <= delta_time;
                        state      <= ST_WAIT;
                    end if;

                when ST_WAIT =>
                    -- Count down using 48 kHz sample ticks
                    if sample_tick = '1' then
                        if tick_count <= 1 then
                            state <= ST_EXECUTE;
                        else
                            tick_count <= tick_count - 1;
                        end if;
                    end if;

                when ST_EXECUTE =>
                    -- Fire the event
                    evt_valid   <= '1';
                    evt_note_on <= command(0);  -- 0x01 = on, 0x00 = off
                    evt_note    <= note;

                    -- Read next event (rom_ptr already points to next record)
                    state <= ST_READ_DT0;

                when ST_DONE =>
                    playing <= '0';
                    -- Stay here until reset or new start
                    if start = '1' then
                        rom_ptr <= (others => '0');
                        state   <= ST_READ_DT0;
                        playing <= '1';
                    end if;

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
