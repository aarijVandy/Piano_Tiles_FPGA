# Piano Tiles FPGA - System Architecture

This project implements a highly optimized, hardware-based version of Piano Tiles upon the DE2-115 board using VHDL logic streams without software RAM framebuffers.

## I/O Map
- **BTN0 - BTN3**: User input mapped to lanes 0 through 3.
- **SW0**: Master board reset switch (asynchronously re-triggers the menu).
- **HEX0 - HEX3**: Displays the player's 4-digit BCD Score natively on the board.
- **LEDG0 - LEDG3**: Green LEDs indicating if an active tile is currently inside the playable "Hit Zone" for lanes 0-3.
- **VGA Output**: Renders playfield output via a continuous hardware combinational pipeline updating at 60Hz.

## Module Pipeline

### Model (Game Engine)
- `DE2_115_TOP.vhd` (Top Level): Contains the master structural integration and physical pin assignments. Implements a finite state machine (`game_state` = `MENU` | `PLAYING`) that acts as a central video MUX (swapping the VGA pins between the menu rendering and game rendering channels). Game loop is governed explicitly by the 60Hz VGA Vertical Blanking pulse to prevent teardown and physics jitter.
- `piano_tiles.vhd`: The core mathematical physics engine traversing a 60Hz tick sequence. Operates a 32-bit LFSR randomized spawner. It tracks and evaluates hits against a perfectly optimized 2D grid matrix. Contains dynamic mathematics dictating continuous difficulty-escalation (expanding time-based penalties and a scaling combo multiplier bonus `+combo/4`). "Phantom button" holding logic is seamlessly bypassed during memory wipes by capturing raw button states synchronously on resets.

### View (Rendering)
- **BCD Decoders**: Takes abstract engine integer logic and maps it natively to 7-Segment board LEDs.
  - `score_to_bcd.vhd`: Converts raw integer scores and counters into 4-digit discrete BCD vectors efficiently using scaling structures.
- **Graphic Renderers (Combinational)**: All RGB pixel arrays are evaluated entirely combinatorally on the fly with static bounding calculations.
  - `tile_renderer.vhd`: Draws the lanes, background separators, falling tiles, and static hit buffers. Utilizing strict binary "Power of Two" grid optimizations (`LANE_WIDTH = 64`, `NOTE_PX_H = 128`), the system avoids creating slow hardware combination division arrays, mapping calculations explicitly into instantaneous O(1) bit-shifting paths. Tiles transition to vibrant Green upon successful hits. The matrix rendering anchor is shifted cleanly to the left quadrant to permit unobstructed HUD rendering.
  - `font_rom.vhd`: A lightweight 6-bit lookup ROM containing matrices for digits (0-9), alphabetical characters (A-Z), and UI symbols. 
  - `vga_score_display.vhd`: HUD overlay renderer rendering string layouts (`MAX`, `SCORE`, `COMBO`, `BEST`) populated by their corresponding scaling values anchored in the rightmost quadrant.
  - `menu_renderer.vhd`: Generates a static instructional Splash Screen matrix vertically interleaving instructions (including Combo rules via 24px precision offsets) terminating in a hardware blink-timer `PRESS START` prompt.

## Synchronization Protocol
- We utilize the `VGA_SYNC.VHD` controller via an internal Phase-Locked Loop (PLL) transforming the board's native `50MHz` crystal array into a **`65MHz` pixel clock** (industry standard for smooth XGA graphics).
- **V-Sync Game Loop:** To emulate flawless zero-lag physics, the central Game Matrix logic steps forward exactly once every `60Hz` pulse natively triggered by the VGA `vert_sync_int` sweeping vertical-edge tracker.
