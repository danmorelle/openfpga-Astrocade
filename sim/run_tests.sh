#!/bin/bash
# Whole-core tests with the generated test BIOS and cartridges (no Bally
# or Astrocade ROMs):
#   * picture size and the APF video protocol
#   * the BIOS and cartridge slots load and the cartridge runs
#   * buttons, the Select shift and the knob reach the console
#   * reloading a smaller cartridge leaves nothing behind
#   * the Reset setting, controller swapping, sound
set -e
cd "$(dirname "$0")"
mkdir -p roms out
python3 make_test_roms.py roms > /dev/null
[ -x obj_dir/Vtb_top ] || ./build.sh > /dev/null

fail=0
colour() {   # log frame side
  grep -o "frame $2: .*" "$1" | grep -o "$3=[0-9a-f]*" | cut -d= -f2
}
expect() {   # log frame side colour description
  local got
  got=$(colour "$1" "$2" "$3")
  if [ "$got" == "$4" ]; then echo "PASS $5"; else echo "FAIL $5 (frame $2 $3: $got, want $4)"; fail=1; fi
}
expect_line() {   # log pattern description
  if grep -q "$2" "$1"; then echo "PASS $3"; else echo "FAIL $3"; fail=1; fi
}

# Colours the test cartridge shows (Astrocade palette through the core)
IDLE=ff00bb TRIG=44ffff UP=ffaaff KEY1=ffcc33 KEY5=2277ff EQ=22ff22 MARK=44aa00
KNOB_CENTRE=ffff44 KNOB_RIGHT=000000 KNOB_LEFT=ddeeff

# Pocket key bits: up 0x1, A 0x10, B 0x20, Y 0x80, R 0x200, Select 0x4000, Start 0x8000
./obj_dir/Vtb_top +frames=26 +out=out/keys \
  +press0=2,2,10 +press1=5,2,1 +press2=8,2,20 +press3=11,2,4080 +press4=14,2,8000 \
  +press5=17,4,200 +press6=22,2,4010 > out/keys.log 2>&1
expect_line out/keys.log "frame 0: hs=26[23] de_lines=230 width min=180 max=180" "picture is 180 x 230"
expect_line out/keys.log "APF video protocol errors: 0" "APF video protocol"
if grep -q "rgb not zero outside de" out/keys.log; then echo "FAIL rgb outside DE"; fail=1; else echo "PASS rgb zero outside DE"; fi
expect out/keys.log 1  right $IDLE "BIOS jumps to the cartridge (idle colour)"
expect out/keys.log 1  left  $KNOB_CENTRE "knob starts centred"
expect out/keys.log 3  right $TRIG "A = trigger"
expect out/keys.log 6  right $UP   "D-pad up"
expect out/keys.log 9  right $KEY1 "B = keypad 1"
expect out/keys.log 12 right $KEY5 "Select+Y = keypad 5"
expect out/keys.log 15 right $EQ   "Start = keypad ="
left21=$(colour out/keys.log 21 left); left25=$(colour out/keys.log 25 left)
if [ "$left21" != "$KNOB_CENTRE" ] && [ "$left21" == "$left25" ]; then
  echo "PASS R turns the knob and it stays put"; else echo "FAIL knob ($left21 / $left25)"; fail=1; fi
expect out/keys.log 23 right $IDLE "Select+A = keypad 6, not the trigger"
changes=$(grep -o "sound output changes: [0-9]*" out/keys.log | grep -o "[0-9]*$")
if [ "$changes" -gt 50 ]; then echo "PASS tone generator ($changes changes)"; else echo "FAIL tone generator"; fail=1; fi

./obj_dir/Vtb_top +frames=3 +out=out/an_r +analog=1 +joy1=000000FF > out/an_r.log 2>&1
./obj_dir/Vtb_top +frames=3 +out=out/an_l +analog=1 +joy1=00000000 > out/an_l.log 2>&1
expect out/an_r.log 2 left $KNOB_RIGHT "Dock stick right turns the knob right"
expect out/an_l.log 2 left $KNOB_LEFT  "Dock stick left turns the knob left"

./obj_dir/Vtb_top +frames=4 +out=out/swap +swap=1 +press0=1,3,10 > out/swap.log 2>&1
expect out/swap.log 2 right $IDLE "swapped: controller 1 is player 2"

./obj_dir/Vtb_top +cart=roms/test_cart8k.bin +frames=7 +out=out/reload \
  +reload=3,roms/test_cart.bin +poke=5,40000000,1 > out/reload.log 2>&1
expect out/reload.log 2 right $MARK "8 KB cartridge loaded"
expect out/reload.log 4 right $IDLE "reload: nothing left over past the end of the 4 KB file"
expect_line out/reload.log "\[frame 5\] core running" "Reset restarts the console"
expect out/reload.log 6 right $IDLE "runs again after Reset"

iverilog -g2012 -o out/input_test.vvp input_test.v ../src/fpga/core/pocket/input_map.v
res=$(vvp out/input_test.vvp | grep "input_test:")
echo "$res"
echo "$res" | grep -q ", 0 errors" || fail=1

if [ $fail == 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; exit 1; fi
