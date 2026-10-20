# Bally Astrocade for Analogue Pocket

An openFPGA core for the Analogue Pocket that recreates the Bally Astrocade
(also sold as the Bally Professional Arcade), a 1978 home console built around
a Z80 CPU and Bally's custom video and sound chips. It is a port of the
[MiSTer Astrocade core](https://github.com/MiSTer-devel/Astrocade_MiSTer).

**Status: 0.1.0, first release.** Tested in simulation and on a Pocket (the
BIOS menu and Muncher).

## Installing

1. Download the latest release zip and copy its contents to the root of your
   Pocket's SD card.
2. Put the Astrocade BIOS in `Assets/astrocade/common/` named exactly
   `astrocade.rom`. It must be the 8 KB BIOS, often called `astro.bin` or
   `astrocade.bin`, so rename it. It is not included. **If the screen stays
   black after loading a game, the BIOS is missing or has the wrong name**
   (the Pocket does not warn about it).
3. Put your cartridge images (`.bin`, up to 8 KB) in the same folder.

## Controls

| Pocket | Astrocade |
|---|---|
| D-pad | Joystick |
| A | Trigger |
| L / R | Turn the knob left / right |
| B / X / Y | Keypad 1 / 2 / 3 |
| Start | Keypad = |
| Hold Select + X / Y / A / B | Keypad 4 / 5 / 6 / 7 |
| Hold Select + Up / Right / Down | Keypad 8 / 9 / 0 |
| Hold Select + Left | Keypad CE |
| Hold Select + L / R / Start | Keypad - / + / C |

The Astrocade's hand controller has a knob on top of the joystick. On the
Pocket, L and R turn it (a full turn takes about a second) and it stays where
you leave it, like the real one. A Dock controller's left analog stick turns
it directly. Up to four controllers work in the Dock.

To pick a game from the menu, press its number on the keypad, or pull the
trigger, turn the knob to the number and pull the trigger again.

## Settings (Core Settings menu)

* **Reset (Game Menu)**: the console's reset button, which brings back the
  game menu.
* **Swap Controllers 1+2**

## How the port works

On MiSTer, the ARM processor loads the BIOS and the cartridge into block RAM.
Here the Pocket does that through two data slots:

* `src/fpga/core/pocket/slot_loader.v` receives the BIOS and the cartridge
  from the Pocket into dual clock RAMs that the console reads like ROM. Bytes
  past the end of a file read as 0, so nothing is left over from a bigger
  cartridge loaded earlier.
* `input_map.v` maps the Pocket and Dock controllers to the hand controls,
  the knob and the keypad, which go through the MiSTer core's switch matrix.
* `core_top.v` samples the picture at 3.58 MHz and shows the same 180 x 230
  area as MiSTer; `video_apf.v` and `audio_apf.v` adapt video and sound to the
  Pocket.
* The console itself (`src/fpga/core/astrocade/`) is an unchanged copy of the
  MiSTer core (commit `5173e50`).

## Building

The GitHub Actions workflow builds the core with Quartus Prime Lite 21.1 in
Docker and uploads an SD card ready zip. Publishing a release tagged
`v<version>` (matching `core.json`) attaches the zip to the release. To build
locally, open `src/fpga/ap_core.qpf` in Quartus Prime Lite, compile, then run
`python3 tools/package.py` to create `release/sd/`.

## Simulation

`sim/` runs the whole core with GHDL and Verilator, loading a BIOS and a
cartridge over a simulated Pocket bridge and saving every frame as an image.
The tests use a small BIOS and cartridges written for them
(`sim/make_test_roms.py`), so no Astrocade ROMs are needed:

```
cd sim
./build.sh
./run_tests.sh
```

They check the picture size and the Pocket's video rules, the BIOS and
cartridge slots, every button, the Select shift, the knob (shoulder buttons
and analog stick), controller swapping, reloading a smaller cartridge, the
Reset setting and the sound output. A few constructs that Quartus accepts but
GHDL does not are fixed in temporary copies for the simulation only (see
`sim/build.sh`).

## Credits and licence

* Bally Astrocade FPGA design: MikeJ (fpgaarcade.com)
* T80 Z80 CPU: Daniel Wallner and contributors
* MiST port: wsoltys; MiSTer port: Kitrinx and contributors
* Pocket port: this repository
* Audio I2S and helper design based on Analogue's openFPGA core template and
  Adam Gastineau's analogue-pocket-utils (MIT)

Released under the GNU GPL v3 (see `LICENSE`), like the MiSTer Astrocade core.
MikeJ's and Daniel Wallner's VHDL files keep their own BSD-style notices,
which must be kept with the source and reproduced with any built core. The
files in `src/fpga/apf/` are Analogue's openFPGA framework.

This core does not include any BIOS or game ROMs.
