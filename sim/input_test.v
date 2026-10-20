//
// Unit test for input_map.v: every button, the Select shift, the knob
// (shoulder buttons and analog stick) and controller swapping.
//
//   iverilog -g2012 -o out/input_test.vvp input_test.v ../src/fpga/core/pocket/input_map.v
//   vvp out/input_test.vvp
//

`timescale 1ns/1ps

module input_test;
  reg clk = 0;
  always #5 clk = ~clk;

  reg  [31:0] k1 = 32'h1000_0000, k2 = 32'h1000_0000, j1 = 32'h80808080, j2 = 32'h80808080;
  reg         swap = 0;
  wire [31:0] ja, jb, jc, jd;
  wire [7:0]  pa, pb, pc, pd;

  input_map dut (.clk(clk), .cont1_key(k1), .cont2_key(k2), .cont3_key(32'd0), .cont4_key(32'd0),
                 .cont1_joy(j1), .cont2_joy(j2), .cont3_joy(32'd0), .cont4_joy(32'd0),
                 .swap12(swap), .joya(ja), .joyb(jb), .joyc(jc), .joyd(jd),
                 .pda(pa), .pdb(pb), .pdc(pc), .pdd(pd));
  defparam dut.m1.KNOB_STEP = 16'd2;
  defparam dut.m2.KNOB_STEP = 16'd2;

  localparam UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, A = 4, B = 5, X = 6, Y = 7,
             L1 = 8, R1 = 9, SEL = 14, START = 15;
  localparam [31:0] POCKET = 32'h1000_0000;

  integer errors = 0, checks = 0;

  task check(input [31:0] got, input [31:0] expv, input [8*40-1:0] what);
    begin
      checks = checks + 1;
      if (got !== expv) begin
        errors = errors + 1;
        $display("FAIL %0s: got %08x expected %08x", what, got, expv);
      end
    end
  endtask

  task press(input [31:0] keys, input [31:0] expv, input [8*40-1:0] what);
    begin
      k1 = POCKET | keys;
      repeat (2) @(posedge clk);
      check(ja, expv, what);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    press(1 << UP,    1 << 3,  "up");
    press(1 << DOWN,  1 << 2,  "down");
    press(1 << LEFT,  1 << 1,  "left");
    press(1 << RIGHT, 1 << 0,  "right");
    press(1 << A,     1 << 4,  "A = trigger");
    press(1 << B,     1 << 6,  "B = 1");
    press(1 << X,     1 << 7,  "X = 2");
    press(1 << Y,     1 << 8,  "Y = 3");
    press(1 << START, 1 << 22, "Start = equals");
    press(1 << L1,    0,       "L turns the knob only");
    press(1 << R1,    0,       "R turns the knob only");

    press((1 << SEL) | (1 << X),     1 << 9,  "Select+X = 4");
    press((1 << SEL) | (1 << Y),     1 << 10, "Select+Y = 5");
    press((1 << SEL) | (1 << A),     1 << 11, "Select+A = 6");
    press((1 << SEL) | (1 << B),     1 << 12, "Select+B = 7");
    press((1 << SEL) | (1 << UP),    1 << 13, "Select+Up = 8");
    press((1 << SEL) | (1 << RIGHT), 1 << 14, "Select+Right = 9");
    press((1 << SEL) | (1 << DOWN),  1 << 5,  "Select+Down = 0");
    press((1 << SEL) | (1 << LEFT),  1 << 17, "Select+Left = CE");
    press((1 << SEL) | (1 << L1),    1 << 19, "Select+L = minus");
    press((1 << SEL) | (1 << R1),    1 << 18, "Select+R = plus");
    press((1 << SEL) | (1 << START), 1 << 16, "Select+Start = C");
    press(0, 0, "release");

    // knob: starts in the middle (pot 0x7F), R turns right (pot falls)
    check({24'd0, pa}, 32'h7F, "knob starts centred");
    k1 = POCKET | (1 << R1);
    repeat (2000) @(posedge clk);
    check({24'd0, pa}, 32'h00, "R: knob fully right, stops at the end");
    k1 = POCKET;
    repeat (20) @(posedge clk);
    check({24'd0, pa}, 32'h00, "knob stays where it was left");
    k1 = POCKET | (1 << L1);
    repeat (2000) @(posedge clk);
    check({24'd0, pa}, 32'hFF, "L: knob fully left, stops at the end");
    k1 = POCKET | (1 << SEL) | (1 << R1);
    repeat (20) @(posedge clk);
    check({24'd0, pa}, 32'hFF, "Select+R does not turn the knob");

    // analog stick: absolute position, Dock analog controllers only
    k1 = 32'h3000_0000; j1 = 32'h0000_00FF;
    repeat (3) @(posedge clk);
    check({24'd0, pa}, 32'h00, "stick right");
    j1 = 32'h0000_0000;
    repeat (3) @(posedge clk);
    check({24'd0, pa}, 32'hFF, "stick left");
    j1 = 32'h0000_0080;
    repeat (3) @(posedge clk);
    check({24'd0, pa}, 32'h7F, "stick centre");

    // swap controllers 1 and 2 (hand controls and knobs)
    k1 = POCKET | (1 << A); k2 = POCKET | (1 << UP); swap = 1;
    repeat (3) @(posedge clk);
    check(ja, 1 << 3, "swap: player 1 gets controller 2");
    check(jb, 1 << 4, "swap: player 2 gets controller 1");
    check({24'd0, pb}, 32'h7F, "swap: knobs follow");
    swap = 0;
    repeat (3) @(posedge clk);
    check(ja, 1 << 4, "no swap");

    $display("input_test: %0d checks, %0d errors", checks, errors);
    $finish;
  end
endmodule
