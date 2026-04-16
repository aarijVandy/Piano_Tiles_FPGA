# Piano Tiles FPGA - System Architecture

This project implements a hardware-based version of Piano Tiles upon the DE2-115 board using VHDL.

## I/O Map
- **BTN0 - BTN3**: User input mapped directly to lanes 0 through 3.
- **SW0**: (Planned) Master board reset switch.
- **HEX0 - HEX3**: Displays the player's 4-digit BCD Score.
- **LEDG0 - LEDG3**: Green LEDs indicating if a tile is currently in the "Hit Zone" for lanes 0-3.
- **VGA Output**: Renders playfield output via a continuous hardware pipeline.

## Module Pipeline

### Model (Game Engine)
- `DE2_115_TOP.vhd` (Top Level): Contains the master Structural integration and physical pin assignments. Implements a finite state machine (`game_state` = `MENU` | `PLAYING`) that holds the game until a start button is pressed. Also drives the 160Hz Game Loop tick.
- `piano_tiles.vhd`: The core gameplay engine monitoring inputs and managing lanes. Evaluates random tile generation (supporting easy-mode tweaks), shifts lanes over a `NOTE_HEIGHT` tick, calculates `score` and `max_score`, and maintains consecutive streak variables `combo` and `best_combo`.

### Controller (Inputs)
- `button_input.vhd`: Translates raw physical switch closures into debounced single-tick pulses.

### View (Rendering)
- **BCD Decoders**: Takes abstract integer logic directly mapped to segments for 7-Segment LEDs.
- `score_to_bcd.vhd`: Converts raw integer scores and combo trackers into 4-digit discrete BCD vectors efficiently using `/ 10` sequences without overlapping.
- `tile_renderer.vhd`: Draws the lanes, background separators, and standard Piano Tiles utilizing hardcoded positional dimensions. Outputs continuous RGB pixel sweeps.
- `font_rom.vhd`: A lightweight 6-bit lookup ROM containing bitmaps for digits (0-9), alphabetical characters (A-Z), and symbols. 
- `vga_score_display.vhd`: A combinational rendering module overlaying descriptive text (MAX, SCORE, COMBO, BEST) with their corresponding tracker amounts. Supports Left-justified labels and Right-justified dynamic digits.
- `menu_renderer.vhd`: Generates a static instructional Splash Screen centered horizontally and vertically on screen, featuring a 1Hz blinking start prompt.

## Synchronization Protocol
- We use the `VGA_SYNC.VHD` controller to generate synchronization vectors across all modules, unifying them at `50MHz`. 
- An overall Game Loop is reduced to `160Hz` through a Clock Divider in `DE2_115_TOP.vhd` to give humane timing intervals.
