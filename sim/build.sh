#!/bin/bash
# Build the whole-core simulation (GHDL converts the VHDL core to Verilog,
# Verilator simulates everything together).
#
# Three things Quartus accepts but GHDL does not are fixed in temporary
# copies (work_src/), never in the real sources:
#   * T80.vhd / T80s.vhd instantiate entities as "label : work.X"
#   * T80.vhd and bally_io.vhd each AND two vectors of different lengths
# and bram.vhd (Intel altsyncram) is replaced by patched/bram_sim.vhd.
set -e
cd "$(dirname "$0")"

GHDL_FLAGS="--std=93c -fsynopsys -fexplicit -frelaxed --workdir=work"
A=../src/fpga/core/astrocade

if [ ! -f bally_synth.v ] || [ "$1" == "vhdl" ]; then
  rm -rf work work_src && mkdir work work_src
  for f in T80.vhd T80s.vhd; do
    sed -E 's/^(\s*[A-Za-z0-9_]+\s*:\s*)work\./\1entity work./' $A/T80/$f > work_src/$f
  done
  sed -i 's/ioq := (ioq and x"7") xor/ioq := (ioq and "000000111") xor/' work_src/T80.vhd
  sed 's/(noise_gen(7 downto 7) and r_snd(7)(7 downto 4))/((noise_gen(7) \& noise_gen(7) \& noise_gen(7) \& noise_gen(7)) and r_snd(7)(7 downto 4))/' \
    $A/bally_io.vhd > work_src/bally_io.vhd
  ghdl -i $GHDL_FLAGS $A/T80/T80_Reg.vhd $A/T80/T80_MCode.vhd $A/T80/T80_ALU.vhd \
    work_src/T80.vhd work_src/T80s.vhd patched/bram_sim.vhd \
    $A/bally_col_pal.vhd $A/bally_rams.vhd work_src/bally_io.vhd \
    $A/bally_addr.vhd $A/bally_data.vhd $A/bally.vhd
  ghdl -m $GHDL_FLAGS bally > /dev/null 2>&1
  ghdl --synth $GHDL_FLAGS --out=verilog bally > bally_synth.v 2> synth.log
  python3 fix_synth.py bally_synth.v
  # GHDL turns VHDL assertions into $fatal calls, which Verilator does not
  # accept in Verilog-2005 files: drop them.
  sed -i 's/\$fatal(1, "assertion failure [a-z0-9]*");/;/' bally_synth.v
fi

POCKET=../src/fpga/core/pocket
verilator --binary --timing -j 2 -O2 +1364-2005ext+v \
  -Wno-fatal -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
  -Wno-CASEINCOMPLETE -Wno-COMBDLY -Wno-INITIALDLY -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME \
  --top-module tb_top \
  tb_top.sv sim_stubs.v \
  ../src/fpga/apf/common.v \
  ../src/fpga/core/core_top.v \
  $POCKET/slot_loader.v $POCKET/input_map.v $POCKET/video_apf.v $POCKET/audio_apf.v \
  $A/Astrocade_input.sv \
  bally_synth.v \
  -o Vtb_top 2>&1 | grep -E '%Error' | head -20 || true
[ -x obj_dir/Vtb_top ] && echo "built obj_dir/Vtb_top"
