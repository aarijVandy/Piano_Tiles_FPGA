# MIDI Audio Pipeline

## High-Level Overview

The goal of this pipeline is simple: **play a MIDI song through the physical audio output jack on the DE2-115 board.**

MIDI files don't contain audio — they contain a list of musical instructions like "play note 69 (A4) at time 0, stop at time 500ms." The pipeline's job is to convert those instructions into actual audio waveforms in real time.

Here is the data flow from ROM to speaker:

```
MIDI ROM ──► Sequencer ──► Voice Allocator ──► 8× DDS Oscillators ──► Mixer ──► I2S TX ──► WM8731 Codec ──► Speaker
```

Each stage transforms the data one step closer to an analog audio signal:

| Stage | Input | Output | Why it exists |
|---|---|---|---|
| **MIDI ROM** | Address | Raw bytes | Stores the song |
| **Sequencer** | Raw bytes + 48 kHz tick | Note on/off events | Parses and times the song |
| **Voice Allocator** | Note events | 8 active voice configs | Handles polyphony (multiple simultaneous notes) |
| **DDS Oscillators** | Phase step per voice | Sine wave samples | Generates the actual audio waveform per note |
| **Mixer** | 8 parallel samples | 1 combined sample | Combines voices into one audio stream |
| **I2S TX** | 16-bit samples at 48 kHz | Serial audio bits | Speaks the protocol the codec understands |
| **WM8731 Codec** | Serial bits | Analog audio | Converts digital to actual sound |

One important enabler runs outside this data path: the **I2C Config** block configures the codec over I2C at startup (setting volume, sample rate, etc.) before any audio plays. Nothing sounds until it finishes.

---

## Clocking — The Shared Heartbeat

Everything in the audio pipeline is clocked from a **12.288 MHz master clock** (`aud_mclk`) synthesized by a PLL from the board's 50 MHz oscillator. This exact frequency is intentional:

```
12.288 MHz ÷ 256 = 48,000 Hz  (sample rate)
```

The I2S transmitter divides `aud_mclk` down to generate the bit clock (BCLK at 3.072 MHz) and the left/right word clock (DACLRCK at 48 kHz). The 48 kHz `sample_req` pulse it generates is then fed back upstream to drive everything else — the sequencer counts delta times in 48 kHz ticks, and the oscillators advance their phase accumulators once per tick.

**Why this matters:** All timing in the system — both audio sample timing and MIDI event timing — is derived from the same clock. The song's tempo stays perfectly locked to the sample rate with no drift.

---

## Detailed Component Breakdown

### 1. MIDI ROM — `audio/midi_rom.vhd`

**What it is:** A synchronous read-only memory storing the song as a flat array of bytes.

**Why it exists:** FPGA block RAM is the right place to store a fixed lookup table. The ROM holds preprocessed event data from a Python script (`convert_midi.py`) that was run on a real `.mid` file offline. This avoids parsing variable-length MIDI encoding at runtime, which would be complex and non-deterministic in hardware.

**Format — 5 bytes per event:**
```
Byte [0–2]  Delta time (24-bit big-endian) — number of 48 kHz samples to wait
Byte [3]    Command: 0x01 = note on, 0x00 = note off, 0xFF = end of song
Byte [4]    MIDI note number (0–127)
```

**How it connects:** The Sequencer drives the address bus and reads one byte at a time, one clock cycle of latency per read. The Sequencer's state machine is written specifically to pipeline around that 1-cycle latency.

---

### 2. MIDI Sequencer — `audio/midi_sequencer.vhd`

**What it is:** A 10-state state machine that reads MIDI event records from ROM and fires them at the correct time.

**Why it exists:** MIDI events aren't evenly spaced — each has a "delta time" (how long to wait before firing). The sequencer's job is to measure that time using the 48 kHz `sample_tick` pulse and only emit an event when the countdown reaches zero.

**How it works:**

The state machine advances through the 5 bytes of each record:

```
ST_IDLE ──► ST_READ_DT0 ──► ST_LATCH_DT0 ──► ST_LATCH_DT1 ──► ST_LATCH_DT2
         ──► ST_LATCH_CMD ──► ST_LATCH_NOTE ──► ST_WAIT ──► ST_EXECUTE ──► (next record)
```

- **ST_LATCH_DT0/1/2:** Reads three bytes to assemble a 24-bit delta time value.
- **ST_WAIT:** Counts down `delta_time` using `sample_tick` pulses. One tick = one 48 kHz audio sample period (20.83 μs).
- **ST_EXECUTE:** Pulses `evt_valid` for exactly one clock cycle, simultaneously outputting `evt_note_on` and `evt_note`. Then immediately loads the next record.
- **ST_DONE:** Reached when command byte is 0xFF. Waits for a new `start` pulse.

**Critical detail — ROM latency pipelining:** The ROM takes one cycle to return data after an address is presented. So the sequencer always sets the address in one state and reads the data in the *next* state. This is why there are separate `ST_READ_DT0` and `ST_LATCH_DT0` states — the first presents the address, the second reads the result.

**How it connects:** Receives `sample_tick` from the I2S TX. Drives the ROM address bus. Emits one-cycle-wide event pulses (`evt_valid`, `evt_note_on`, `evt_note`) to the voice allocation logic in `audio_top.vhd`.

---

### 3. Voice Allocator — inside `audio/audio_top.vhd`

**What it is:** Logic that manages 8 independent "voice slots," assigning incoming notes to free slots and releasing them on note-off.

**Why it exists:** Piano music is polyphonic — multiple notes play simultaneously. Each note needs its own oscillator. The allocator is the bookkeeping layer that maps note numbers to oscillator instances.

**State per voice:**
```vhdl
v_active(i)     -- Is this voice currently sounding?
v_note(i)       -- Which MIDI note is it playing? (for note-off matching)
v_phase_acc(i)  -- Current 16-bit phase accumulator (tracks position in the sine wave)
v_phase_step(i) -- How much to advance the phase each sample (encodes the frequency)
```

**2-cycle allocation pipeline:**

When `evt_valid` fires, the allocator cannot immediately configure a voice because it still needs to look up the phase step for the note number (that lookup takes one clock). So it uses a 2-cycle pipeline:

- **Cycle 1 (`evt_valid = '1'):**
  - For note-on: scan `v_active` for the first free slot; latch its index.
  - For note-off: scan `v_note` to find the slot playing this note; latch its index.
  - Set the note lookup table address to `evt_note`.

- **Cycle 2 (`alloc_pending = '1'):**
  - The note table output (`phase_step`) is now valid.
  - Apply the change: activate/deactivate the voice, set `v_phase_step`, reset `v_phase_acc` to 0 on note-on.

**Phase accumulator advancement:** Every time `sample_req` pulses (48 kHz), all active voices have their `v_phase_acc` incremented by their `v_phase_step`. This is what makes each note play at the right frequency.

**How it connects:** Receives events from the Sequencer. Queries the Note Table. Configures voice arrays read by the DDS oscillators.

---

### 4. MIDI Note Table — `audio/midi_note_table.vhd`

**What it is:** A 128-entry lookup table mapping MIDI note numbers to DDS phase step values.

**Why it exists:** The oscillators use Direct Digital Synthesis — they don't know anything about musical notes. They just know "advance my phase by N each sample." The Note Table pre-computes the N for all 128 MIDI notes so the allocator can fetch it in one clock cycle rather than doing floating-point frequency math in hardware.

**The math:** Each phase step is pre-calculated as:
```
step = round( frequency × 65536 / 48000 )

Where:
  frequency = 440 × 2^((note - 69) / 12)   (standard equal temperament tuning)
  65536     = 2^16 (full phase accumulator range, one complete sine cycle)
  48000     = sample rate in Hz
```

Some reference values:

| MIDI Note | Name | Frequency | Phase Step |
|---|---|---|---|
| 60 | C4 (Middle C) | 261.6 Hz | 357 |
| 69 | A4 (concert pitch) | 440.0 Hz | 601 |
| 84 | C6 | 1046.5 Hz | 1429 |

**How it connects:** Receives a note number from the allocator in Cycle 1. Returns a 16-bit phase step one cycle later (registered output), which the allocator reads in Cycle 2. One instance is shared across all voices since allocations are serialized.

---

### 5. DDS Oscillators & Sine ROM — `audio/sine_rom.vhd`

**What it is:** Eight identical wavetable oscillators, each consisting of a 16-bit phase accumulator (in `audio_top`) and a 256-entry sine ROM instance.

**Why it exists:** Direct Digital Synthesis (DDS) is the most resource-efficient way to generate a sine wave in an FPGA. Instead of computing `sin(x)` in real time (expensive), you store one cycle of a sine wave in a lookup table and walk through it at a rate proportional to the desired frequency.

**How DDS works:**
```
Each sample period:
  v_phase_acc(i) += v_phase_step(i)        -- advance position in sine cycle
  addr = v_phase_acc(i)[15:8]              -- top 8 bits = index into 256-entry table
  sample(i) = SINE_ROM[addr]               -- read the amplitude at that position
```

The phase accumulator is 16 bits wide. The sine ROM has 256 entries (8 address bits). Using the *upper* 8 bits of the 16-bit accumulator means:
- The lower 8 bits act as sub-sample interpolation (increases frequency resolution without a larger ROM).
- The accumulator wraps naturally at 65536, which corresponds to exactly one sine cycle.

**Why 8 instances:** Because they are read in parallel every sample period. All 8 voices need their amplitude at the same moment so the mixer can sum them. Sharing a single ROM would require 8 cycles to read 8 values, which would not fit in the 20.83 μs sample window.

**How it connects:** Addresses are driven by the upper 8 bits of each voice's `v_phase_acc`. Outputs (`sine_datas`) feed directly into the mixer.

---

### 6. Mixer — inside `audio/audio_top.vhd`

**What it is:** A combinational adder tree that sums all active voice samples into one output sample.

**Why it exists:** The audio codec expects a single audio stream, not 8 independent ones. The mixer combines them while preventing integer overflow.

**How overflow is avoided:**
- Each sine sample is 16-bit signed (±32767).
- Before adding, each active voice is **right-shifted by 3** (divided by 8): `v_gated(i) = sine(i) >> 3`.
- This scales each voice down so that 8 voices at full amplitude still fit in 16 bits.
- The shifted values are then added in a binary tree to minimize carry-chain delay:

```
v0 + v1 ──► sum_01 ─┐
v2 + v3 ──► sum_23 ─┴──► sum_0123 ─┐
v4 + v5 ──► sum_45 ─┐               ├──► sum_all[15:0] ──► audio output
v6 + v7 ──► sum_67 ─┴──► sum_4567 ─┘
```

Inactive voices contribute zero (the gate suppresses them before the adder tree).

**How it connects:** Reads `sine_datas` and `v_active`. The final 16-bit output is driven to both left and right channels of the I2S transmitter (mono output).

---

### 7. I2S Transmitter — `audio/audio_i2s_tx.vhd`

**What it is:** A serial transmitter that converts 16-bit left/right samples into the I2S protocol expected by the WM8731 codec.

**Why it exists:** The WM8731 audio codec communicates over I2S — a simple 3-wire serial bus (BCLK, DACLRCK, DACDAT). The FPGA can't just hand it a parallel bus; it needs to serialize samples MSB-first with precise timing.

**Clock derivation from 12.288 MHz MCLK:**
```
MCLK (12.288 MHz)
  ÷ 4  ──► BCLK (3.072 MHz, the serial bit clock)
  ÷ 64 ──► DACLRCK (48 kHz, the left/right word clock)
```

**Frame structure (256 MCLK cycles per frame):**
```
BCLK index:   0         1–16         17–31     32        33–48        49–63
              (gap)   Left channel  (zeros)   (gap)   Right channel  (zeros)
DACLRCK:      ────────────── LOW ──────────────────────── HIGH ──────────────
```

**Critical `sample_req` timing:** The transmitter pulses `sample_req` at MCLK cycle 252 — 4 cycles *before* the end of the current frame. This gives `audio_top` time to:
1. Advance all phase accumulators.
2. Let the sine ROM pipeline its new samples.
3. Compute the mixer output.
4. Latch the result before it's needed at the start of the next frame.

**How it connects:** Receives `left_data`/`right_data` from the mixer. Drives `AUD_BCLK`, `AUD_DACLRCK`, `AUD_DACDAT` directly to the codec pins. Feeds `sample_req` back upstream to the Sequencer (as `sample_tick`) and to the phase accumulator advancement logic.

---

### 8. I2C Config — `audio/audio_i2c_config.vhd`

**What it is:** An I2C master that writes 10 configuration registers to the WM8731 codec at startup.

**Why it exists:** The WM8731 is highly configurable (input routing, sample rate, volume, power). It does not have default settings suitable for audio playback. Before any audio can play, 10 specific registers must be written over I2C to:
- Power up the correct subsystems.
- Select the DAC signal path.
- Set the audio interface to I2S mode, 16-bit, 48 kHz.
- Activate the codec.
- Set headphone volume to 0 dB.

**Startup sequence:**
1. Wait ~20 ms after reset (lets the codec stabilize after power-up).
2. Write 10 registers sequentially. Each write = I2C START + device address + reg address byte + data byte + STOP.
3. Assert `done = '1'`. Audio operations in `audio_top` are gated on `i2c_done` — nothing plays until this completes.

**I2C timing:**
- 50 MHz ÷ 125 = 400 kHz tick rate (4 phases per bit → 100 kHz effective I2C clock).
- WM8731 address: `0x1A` (7-bit).

**How it connects:** Uses `CLOCK_50` (independent of audio clock, ensuring I2C runs even before the PLL locks). Drives `I2C_SCLK` and `I2C_SDAT` (open-drain) to the codec. Drives `done` signal that gates all playback in `audio_top`.

---

## Component Interaction Diagram

```
                        ┌─────────────────────────────────────────────────────────┐
 50 MHz ──► audio_pll ──► 12.288 MHz (aud_mclk)                                   │
                         │                                                         │
                         │  ┌─────────────────────────────────────────────────┐   │
                         └─►│                  audio_top                       │   │
                            │                                                  │   │
   start/stop keys ────────►│                                                  │   │
                            │  ┌────────────┐  evt_valid    ┌──────────────┐  │   │
                            │  │   midi_    │  evt_note ───►│    Voice     │  │   │
             rom_addr ◄─────│  │ sequencer  │  evt_note_on  │  Allocator   │  │   │
             rom_data ─────►│  └─────┬──────┘               └──────┬───────┘  │   │
                            │        │ sample_tick                  │ note_num │   │
                            │  ┌─────▼──────┐                ┌─────▼───────┐  │   │
                            │  │  midi_rom  │                │  midi_note  │  │   │
                            │  └────────────┘                │    table    │  │   │
                            │                                └─────┬───────┘  │   │
                            │                                      │ phase_step│  │
                            │           ┌──────────────────────────▼─────────┐│   │
                            │           │   8× voice state (v_phase_acc,     ││   │
                            │           │   v_phase_step, v_active, v_note)  ││   │
                            │           └──────────────────────────┬─────────┘│   │
                            │                                       │ addr     │   │
                            │                               ┌───────▼────────┐ │   │
                            │                               │  8× sine_rom   │ │   │
                            │                               └───────┬────────┘ │   │
                            │                                       │ samples  │   │
                            │                               ┌───────▼────────┐ │   │
                            │                               │     Mixer      │ │   │
                            │                               └───────┬────────┘ │   │
                            │                                       │ 16-bit   │   │
                            │  ◄── sample_req ──────────────┌───────▼────────┐ │   │
                            │                               │  audio_i2s_tx  │ │   │
                            │                               └───────┬────────┘ │   │
                            └───────────────────────────────────────┼──────────┘   │
                                                                     │              │
                                            AUD_BCLK, DACLRCK, DACDAT              │
                                                                     ▼              │
                                                             WM8731 Codec ──► Jack  │
                                                                                    │
 50 MHz ──► audio_i2c_config ──► I2C_SCLK/SDAT ──► WM8731 (startup config only)   │
                        └────────────────────────────────────────────────────────── ┘
```

---

## Key Design Decisions

**Why preprocess MIDI instead of parsing at runtime?**
MIDI uses variable-length encoded delta times (1–4 bytes per event, with a continuation bit per byte). Parsing this correctly in a state machine would be complex and error-prone. Preprocessing with `convert_midi.py` converts everything to fixed-width 5-byte records, making the sequencer simple and deterministic.

**Why 16-bit phase accumulators with a 256-entry sine table?**
Using the upper 8 bits of a 16-bit accumulator as the sine address gives 256× finer frequency resolution than a plain 8-bit accumulator, without needing a larger ROM. The lower 8 bits act as a sub-sample fractional phase.

**Why 8 sine ROM instances instead of one shared ROM?**
All 8 voices need their sine sample at the same clock cycle so the mixer can add them simultaneously. A single ROM can only serve one address per cycle. Eight instances (one per voice) let all samples be read in parallel, keeping latency to one clock cycle.

**Why is `sample_req` early by 4 cycles?**
The pipeline from `sample_req` to valid mixer output takes several cycles:
1. Phase accumulators are advanced (1 cycle).
2. Sine ROM reads (1 cycle latency).
3. Mixer adder tree settles (combinational, but needs to be stable).
The early pulse ensures the new sample is ready and stable when the I2S transmitter begins shifting it out on the next frame boundary.

**Why right-shift by 3 before mixing?**
Eight voices × 16-bit max amplitude (32767) = potential sum of 262,136. A 16-bit signed integer maxes out at 32767. Dividing each voice by 8 (shift right 3) before summing keeps the worst-case total within 16 bits (32767), preventing overflow and clipping.
