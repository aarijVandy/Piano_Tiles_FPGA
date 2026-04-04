-- =============================================================================
-- Audio Top Level for DE2-115 — MIDI File Player
--
-- Plays a MIDI file stored in on-chip ROM through the WM8731 audio codec.
-- The MIDI file is preprocessed by convert_midi.py into a simple event
-- format that eliminates variable-length parsing and tempo math.
--
-- Architecture:
--   MIDI ROM -> Sequencer -> Voice Allocator -> 8x DDS Oscillators
--                                            -> Sine ROM (x8)
--                                            -> Adder Tree Mixer
--                                            -> I2S Transmitter -> WM8731
--
-- Controls:
--   SW[0]  = master reset (up = reset)
--   KEY[0] = play / restart from beginning
--   KEY[1] = stop and silence
--
-- Status LEDs:
--   LEDG[0] = PLL locked
--   LEDG[1] = codec configured
--   LEDG[2] = song playing
--   LEDG[7:3] = active voice count (binary)
--
-- IMPORTANT:
--   1. Create a PLL IP core named "audio_pll" in Quartus (ALTPLL):
--      Input: 50 MHz, Output: 12.288 MHz, Lock output enabled.
--   2. Run: python3 convert_midi.py your_song.mid midi_rom.vhd
--      to generate the MIDI ROM, then add midi_rom.vhd to the project.
--   3. Set MIDI_ROM_ADDR_BITS to match the addr width printed by the script.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_top is
    generic (
        NUM_VOICES         : integer := 8;
        MIDI_ROM_ADDR_BITS : integer := 16  -- match convert_midi.py output
    );
    port (
        CLOCK_50    : in    std_logic;
        SW          : in    std_logic_vector(17 downto 0);
        KEY         : in    std_logic_vector(3 downto 0);

        AUD_XCK     : out   std_logic;
        AUD_BCLK    : out   std_logic;
        AUD_DACLRCK : out   std_logic;
        AUD_DACDAT  : out   std_logic;

        I2C_SCLK    : out   std_logic;
        I2C_SDAT    : inout std_logic;

        LEDG        : out   std_logic_vector(7 downto 0)
    );
end entity audio_top;

architecture rtl of audio_top is

    -- =========================================================================
    -- Constants
    -- =========================================================================
    -- Attenuation per voice: shift right by this many bits.
    -- For 8 voices, shift 3 keeps full-scale sum within 16-bit range.
    constant VOICE_ATTEN_SHIFT : integer := 3;

    -- =========================================================================
    -- Clocks and reset
    -- =========================================================================
    signal aud_mclk   : std_logic;
    signal pll_locked : std_logic;
    signal reset_n    : std_logic;

    -- =========================================================================
    -- Button synchronisation and edge detection
    -- =========================================================================
    signal key_meta      : std_logic_vector(3 downto 0) := "1111";
    signal key_sync      : std_logic_vector(3 downto 0) := "1111";
    signal key_sync_prev : std_logic_vector(3 downto 0) := "1111";
    signal keys_active   : std_logic_vector(3 downto 0);
    signal key_press     : std_logic_vector(3 downto 0);  -- single-cycle pulse on press

    -- =========================================================================
    -- I2C / I2S
    -- =========================================================================
    signal i2c_done   : std_logic;
    signal sample_req : std_logic;
    signal left_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal right_data : std_logic_vector(15 downto 0) := (others => '0');

    -- =========================================================================
    -- MIDI ROM
    -- =========================================================================
    signal midi_rom_addr : std_logic_vector(MIDI_ROM_ADDR_BITS - 1 downto 0);
    signal midi_rom_data : std_logic_vector(7 downto 0);

    -- =========================================================================
    -- MIDI Sequencer
    -- =========================================================================
    signal seq_start    : std_logic := '0';
    signal seq_playing  : std_logic;
    signal evt_valid    : std_logic;
    signal evt_note_on  : std_logic;
    signal evt_note     : std_logic_vector(6 downto 0);

    -- =========================================================================
    -- Note-to-phase-step lookup
    -- =========================================================================
    signal note_lookup_addr : std_logic_vector(6 downto 0);
    signal note_lookup_step : std_logic_vector(15 downto 0);

    -- =========================================================================
    -- Voice management
    -- =========================================================================
    type voice_active_array is array (0 to NUM_VOICES - 1) of std_logic;
    type voice_note_array   is array (0 to NUM_VOICES - 1) of std_logic_vector(6 downto 0);
    type voice_phase_array  is array (0 to NUM_VOICES - 1) of unsigned(15 downto 0);
    type voice_step_array   is array (0 to NUM_VOICES - 1) of unsigned(15 downto 0);

    signal v_active     : voice_active_array := (others => '0');
    signal v_note       : voice_note_array   := (others => (others => '0'));
    signal v_phase_acc  : voice_phase_array  := (others => (others => '0'));
    signal v_phase_step : voice_step_array   := (others => (others => '0'));

    -- Voice allocation pipeline (2-cycle: lookup + assign)
    signal alloc_pending    : std_logic := '0';
    signal alloc_is_on      : std_logic := '0';
    signal alloc_note       : std_logic_vector(6 downto 0) := (others => '0');
    signal alloc_voice_idx  : integer range 0 to NUM_VOICES - 1 := 0;
    signal alloc_voice_valid: std_logic := '0';

    -- =========================================================================
    -- Sine ROM instances (one per voice for parallel readout)
    -- =========================================================================
    type addr_array is array (0 to NUM_VOICES - 1) of std_logic_vector(7 downto 0);
    type data_array is array (0 to NUM_VOICES - 1) of std_logic_vector(15 downto 0);

    signal sine_addrs : addr_array;
    signal sine_datas : data_array;

    -- =========================================================================
    -- Mixer signals (adder tree)
    -- =========================================================================
    type gated_array  is array (0 to NUM_VOICES - 1) of signed(15 downto 0);
    signal v_gated : gated_array;

    signal sum_01, sum_23, sum_45, sum_67     : signed(16 downto 0);
    signal sum_0123, sum_4567                  : signed(17 downto 0);
    signal sum_all                             : signed(18 downto 0);
    signal mix_out                             : std_logic_vector(15 downto 0);

    -- Active voice counter for LED display
    signal active_count : unsigned(3 downto 0);

    -- =========================================================================
    -- PLL component
    -- =========================================================================
    component audio_pll is
        port (
            inclk0 : in  std_logic;
            c0     : out std_logic;
            locked : out std_logic
        );
    end component;

begin

    reset_n <= (not SW(0)) and pll_locked;

    -- =========================================================================
    -- Button sync, edge detect
    -- =========================================================================
    process(aud_mclk, reset_n)
    begin
        if reset_n = '0' then
            key_meta      <= "1111";
            key_sync      <= "1111";
            key_sync_prev <= "1111";
        elsif rising_edge(aud_mclk) then
            key_meta      <= KEY;
            key_sync      <= key_meta;
            key_sync_prev <= key_sync;
        end if;
    end process;

    keys_active <= not key_sync;
    -- Detect press: keys_active rising edge (was released, now pressed)
    key_press <= (not key_sync) and key_sync_prev;

    -- =========================================================================
    -- PLL: 50 MHz -> 12.288 MHz
    -- =========================================================================
    pll_inst : audio_pll
        port map (inclk0 => CLOCK_50, c0 => aud_mclk, locked => pll_locked);

    AUD_XCK <= aud_mclk;

    -- =========================================================================
    -- I2C codec configuration
    -- =========================================================================
    i2c_inst : entity work.audio_i2c_config
        port map (
            clk => CLOCK_50, reset_n => reset_n,
            i2c_sclk => I2C_SCLK, i2c_sdat => I2C_SDAT,
            done => i2c_done
        );

    -- =========================================================================
    -- I2S transmitter
    -- =========================================================================
    i2s_inst : entity work.audio_i2s_tx
        port map (
            mclk => aud_mclk, reset_n => reset_n,
            left_data => left_data, right_data => right_data,
            sample_req => sample_req,
            aud_bclk => AUD_BCLK, aud_daclrck => AUD_DACLRCK,
            aud_dacdat => AUD_DACDAT
        );

    -- =========================================================================
    -- MIDI ROM (generated by convert_midi.py)
    -- =========================================================================
    midi_rom_inst : entity work.midi_rom
        port map (
            clk  => aud_mclk,
            addr => midi_rom_addr,
            data => midi_rom_data
        );

    -- =========================================================================
    -- MIDI Sequencer
    -- =========================================================================
    seq_inst : entity work.midi_sequencer
        generic map (ROM_ADDR_BITS => MIDI_ROM_ADDR_BITS)
        port map (
            clk         => aud_mclk,
            reset_n     => reset_n,
            start       => seq_start,
            sample_tick => sample_req,
            rom_addr    => midi_rom_addr,
            rom_data    => midi_rom_data,
            evt_valid   => evt_valid,
            evt_note_on => evt_note_on,
            evt_note    => evt_note,
            playing     => seq_playing
        );

    -- =========================================================================
    -- Note-to-phase-step lookup table
    -- The address is always driven by the latest event note; the output
    -- becomes valid one MCLK cycle later (used by the alloc pipeline).
    -- =========================================================================
    note_lookup_addr <= evt_note when alloc_pending = '0' else alloc_note;

    note_table_inst : entity work.midi_note_table
        port map (
            clk        => aud_mclk,
            note_num   => note_lookup_addr,
            phase_step => note_lookup_step
        );

    -- =========================================================================
    -- Sine ROM instances (one per voice)
    -- =========================================================================
    gen_sine : for i in 0 to NUM_VOICES - 1 generate
        sine_addrs(i) <= std_logic_vector(v_phase_acc(i)(15 downto 8));
        sine_inst : entity work.sine_rom
            port map (clk => aud_mclk, addr => sine_addrs(i), data => sine_datas(i));
    end generate gen_sine;

    -- =========================================================================
    -- Combinational mixer: gate, attenuate, add tree
    --
    -- Each voice is shifted right by VOICE_ATTEN_SHIFT (3 for 8 voices).
    -- Max per-voice after shift: 32767/8 = 4095.
    -- Max 8-voice sum: 8 * 4095 = 32764 — fits 16-bit signed, no saturation.
    -- =========================================================================
    gen_gate : for i in 0 to NUM_VOICES - 1 generate
        v_gated(i) <=
            shift_right(signed(sine_datas(i)), VOICE_ATTEN_SHIFT)
                when v_active(i) = '1'
            else (others => '0');
    end generate gen_gate;

    sum_01   <= resize(v_gated(0), 17) + resize(v_gated(1), 17);
    sum_23   <= resize(v_gated(2), 17) + resize(v_gated(3), 17);
    sum_45   <= resize(v_gated(4), 17) + resize(v_gated(5), 17);
    sum_67   <= resize(v_gated(6), 17) + resize(v_gated(7), 17);
    sum_0123 <= resize(sum_01, 18)     + resize(sum_23, 18);
    sum_4567 <= resize(sum_45, 18)     + resize(sum_67, 18);
    sum_all  <= resize(sum_0123, 19)   + resize(sum_4567, 19);

    mix_out  <= std_logic_vector(sum_all(15 downto 0));

    -- =========================================================================
    -- Main control process
    --   - Playback start/stop (button handling)
    --   - Voice allocation (note on/off from sequencer)
    --   - Phase accumulator advance (on sample_req)
    --   - Audio output latching
    -- =========================================================================
    process(aud_mclk, reset_n)
        variable found : std_logic;
        variable idx   : integer range 0 to NUM_VOICES - 1;
    begin
        if reset_n = '0' then
            v_active     <= (others => '0');
            v_note       <= (others => (others => '0'));
            v_phase_acc  <= (others => (others => '0'));
            v_phase_step <= (others => (others => '0'));
            left_data    <= (others => '0');
            right_data   <= (others => '0');
            seq_start    <= '0';
            alloc_pending    <= '0';
            alloc_is_on      <= '0';
            alloc_note       <= (others => '0');
            alloc_voice_idx  <= 0;
            alloc_voice_valid<= '0';

        elsif rising_edge(aud_mclk) then

            seq_start <= '0';  -- default: single-cycle pulse

            -- =================================================================
            -- Button controls
            -- =================================================================

            -- KEY[0]: play / restart
            if key_press(0) = '1' and i2c_done = '1' then
                -- Silence all voices and start from beginning
                v_active  <= (others => '0');
                seq_start <= '1';
            end if;

            -- KEY[1]: stop
            if key_press(1) = '1' then
                v_active <= (others => '0');
                -- Sequencer will stop when it sees we're no longer feeding it
                -- (or we rely on reset; for now, just silence voices)
            end if;

            -- =================================================================
            -- Voice allocation — 2-cycle pipeline
            --
            -- Cycle 1 (evt_valid): find free/matching voice, latch request.
            --         Note table address is set; output valid next cycle.
            -- Cycle 2 (alloc_pending): use note table output to configure voice.
            -- =================================================================

            -- Cycle 2: complete the allocation
            if alloc_pending = '1' then
                alloc_pending <= '0';
                if alloc_voice_valid = '1' then
                    if alloc_is_on = '1' then
                        v_active(alloc_voice_idx)     <= '1';
                        v_note(alloc_voice_idx)       <= alloc_note;
                        v_phase_step(alloc_voice_idx) <= unsigned(note_lookup_step);
                        v_phase_acc(alloc_voice_idx)  <= (others => '0');
                    else
                        v_active(alloc_voice_idx) <= '0';
                    end if;
                end if;
            end if;

            -- Cycle 1: latch event and find voice slot
            if evt_valid = '1' then
                alloc_pending <= '1';
                alloc_is_on   <= evt_note_on;
                alloc_note    <= evt_note;

                found := '0';
                idx   := 0;

                if evt_note_on = '1' then
                    -- Find first free voice
                    for i in 0 to NUM_VOICES - 1 loop
                        if v_active(i) = '0' and found = '0' then
                            idx   := i;
                            found := '1';
                        end if;
                    end loop;
                else
                    -- Find voice playing this note
                    for i in 0 to NUM_VOICES - 1 loop
                        if v_active(i) = '1' and v_note(i) = evt_note and found = '0' then
                            idx   := i;
                            found := '1';
                        end if;
                    end loop;
                end if;

                alloc_voice_idx   <= idx;
                alloc_voice_valid <= found;
            end if;

            -- =================================================================
            -- Phase advance and audio output (on each 48 kHz sample tick)
            -- =================================================================
            if sample_req = '1' and i2c_done = '1' then
                -- Advance phase accumulators for all active voices
                for i in 0 to NUM_VOICES - 1 loop
                    if v_active(i) = '1' then
                        v_phase_acc(i) <= v_phase_acc(i) + v_phase_step(i);
                    end if;
                end loop;

                -- Latch mixer output
                left_data  <= mix_out;
                right_data <= mix_out;
            end if;

        end if;
    end process;

    -- =========================================================================
    -- Active voice counter (for LED display)
    -- =========================================================================
    process(v_active)
        variable cnt : unsigned(3 downto 0);
    begin
        cnt := (others => '0');
        for i in 0 to NUM_VOICES - 1 loop
            if v_active(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        active_count <= cnt;
    end process;

    -- =========================================================================
    -- Status LEDs
    -- =========================================================================
    LEDG(0) <= pll_locked;
    LEDG(1) <= i2c_done;
    LEDG(2) <= seq_playing;
    LEDG(3) <= active_count(0);
    LEDG(4) <= active_count(1);
    LEDG(5) <= active_count(2);
    LEDG(6) <= active_count(3);
    LEDG(7) <= '0';

end architecture rtl;