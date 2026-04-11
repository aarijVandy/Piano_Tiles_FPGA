# Piano Tiles Implemented on FPGA Board

## 1. Overview

Implement a **Piano Tiles** style game on an FPGA with **4 vertical lanes**. A single tile falls downward over time, and the player must press the correct lane button when that tile is within an acceptance **buffer zone** near the bottom of the screen. The game must support restarting at any time via **SW0**.

This version uses **single-tile gameplay**:

- At any given moment, there is **only one active tile on the screen horizontally**
- That means only **one lane contains a falling tile at a time**
- No simultaneous tiles in multiple lanes
- A new tile may spawn only after the previous tile has been either:
  - successfully hit, or
  - missed by passing beyond the valid region

This keeps the game logic simple, fair, and fully single-press.

---

## 2. Hardware / I/O Requirements

### 2.1 Inputs

- **BTN0..BTN3**: one button per lane
- **SW0**: global restart switch

### 2.2 Outputs

Use the board's available display output:

- **VGA / HDMI video output**, or
- **LED matrix output**

The display must show the 4 lanes, the falling tile, the hit zone, and the score counters.

---

## 3. Display / Playfield Requirements

### 3.1 Lanes

- The playfield contains **exactly 4 vertical lanes**
- Lanes are arranged side by side across the screen
- Each lane has equal width
- Buttons map directly to lanes:
  - **BTN0 → lane 0**
  - **BTN1 → lane 1**
  - **BTN2 → lane 2**
  - **BTN3 → lane 3**

### 3.2 Tile Geometry

Define:

- `SCREEN_W` = screen width
- `SCREEN_H` = screen height
- `LANE_W = SCREEN_W / 4`
- `T` = tile height

Each tile must satisfy:

- fixed width = exactly one lane width
- fixed height = `T`
- occupies exactly one lane
- represented by:
  - lane index
  - vertical position `y`
  - active flag

The tile begins near the top of the screen and moves downward over time.

### 3.3 Single Active Tile Rule

The system must enforce the following rule:

- **Only one tile may be active on the entire screen at a time**
- There must never be:
  - two tiles in different lanes at once
  - two stacked tiles in the same lane
  - overlapping active tiles of any kind

So the full game loop is:

1. Spawn one tile in one pseudo-random lane
2. Let it fall downward
3. Wait until the player hits it or it is missed
4. Remove that tile
5. Spawn the next tile

This is a strict design requirement.

### 3.4 Buffer (Hit) Zone

A hit zone exists at the bottom of the playfield.

- Buffer zone height must equal **`3*T`**
- The zone starts at:
  - `BUFFER_TOP = SCREEN_H - 3*T`
- The zone ends at:
  - `BUFFER_BOTTOM = SCREEN_H`

A press is only considered valid if the active tile is in the correct lane and overlaps this zone according to the hit logic below.

The zone should be visually highlighted so the player clearly sees the valid timing area.

---

## 4. Game Mechanics Requirements

## 4.1 Tile Generation

- Tiles must be generated pseudo-randomly across the 4 lanes
- A simple **LFSR-based PRNG** is acceptable
- Each new tile is assigned exactly one lane index from `0..3`
- The lane choice must appear non-deterministic to the player

Because this version is single-tile-only:

- the game must **not** spawn a new tile while another tile is still active
- spawn logic must check `tile_active == 0` before creating a new tile

Recommended logic:

- If there is no active tile, spawn one at:
  - chosen lane = `rand % 4`
  - initial `y = 0` or `y = -T`
  - `active = 1`

### 4.2 Tile Motion

- The active tile falls from top toward bottom
- Motion must occur on a stable game tick, not directly on raw button timing
- A tile's vertical position updates as:
  - `y_next = y_current + FALL_STEP`

Where:

- `FALL_STEP` is a configurable downward increment
- update timing is controlled by a divided tick or frame tick

Tile speed must be configurable through constants or registers.

### 4.3 Exact Hit Detection Logic

On a debounced rising-edge press of button `BTNn`:

1. Check whether there is an active tile
2. Check whether the tile's lane equals `n`
3. Check whether the tile overlaps the buffer zone

A tile occupies the vertical interval:

- `[y, y + T)`

The buffer zone occupies:

- `[BUFFER_TOP, BUFFER_BOTTOM)`

A valid overlap exists if:

```text
(y + T > BUFFER_TOP) AND (y < BUFFER_BOTTOM)