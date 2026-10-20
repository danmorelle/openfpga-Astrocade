//
// Pocket / Dock controllers -> Astrocade hand controls and keypad
//
// Output layout is the MiSTer core's joystick word (active high), which
// bally_input (Astrocade_input.sv) turns into the console's switch matrix:
//   0 right, 1 left, 2 down, 3 up, 4 trigger,
//   5..14 keypad 0..9, 15 CH, 16 C, 17 CE, 18 +, 19 -, 20 x, 21 /,
//   22 =, 23 ., 24 MR, 25 MS, 26 up arrow, 27 down arrow, 28 %
// The keypad belongs to the console, so every controller can press it.
//
// Button layout (Pocket or Dock controller):
//   D-pad = joystick      A = trigger       L / R = turn the knob
//   B = 1   X = 2   Y = 3   Start = "="
//   Select held as a shift key:
//     X = 4   Y = 5   A = 6   B = 7   Up = 8   Right = 9   Down = 0
//     Left = CE   L = "-"   R = "+"   Start = C
//
// The knob: Dock controllers with analog sticks turn it with the left
// stick (left to right). Otherwise L and R turn it, a full turn taking
// about 0.9 s; it stays where it was left, like the real knob.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pad_map #(
    parameter KNOB_STEP = 16'd50000            // clocks per knob step (14.3 MHz)
) (
    input  wire        clk,
    input  wire [31:0] key,
    input  wire [31:0] joy,

    output reg  [31:0] j,
    output wire [7:0]  pot                     // console pot value
);

  wire up    = key[0];
  wire down  = key[1];
  wire left  = key[2];
  wire right = key[3];
  wire a     = key[4];
  wire b     = key[5];
  wire x     = key[6];
  wire y     = key[7];
  wire l1    = key[8];
  wire r1    = key[9];
  wire sel   = key[14];
  wire start = key[15];

  wire is_analog = (key[31:28] == 4'h3);
  wire shift = sel;

  always @(*) begin
    j = 32'd0;
    if (!shift) begin
      j[0]  = right;
      j[1]  = left;
      j[2]  = down;
      j[3]  = up;
      j[4]  = a;           // trigger
      j[6]  = b;           // 1
      j[7]  = x;           // 2
      j[8]  = y;           // 3
      j[22] = start;       // =
    end else begin
      j[9]  = x;           // 4
      j[10] = y;           // 5
      j[11] = a;           // 6
      j[12] = b;           // 7
      j[13] = up;          // 8
      j[14] = right;       // 9
      j[5]  = down;        // 0
      j[17] = left;        // CE
      j[19] = l1;          // -
      j[18] = r1;          // +
      j[16] = start;       // C
    end
  end

  // ---- Knob position: 0 = turned fully left, 255 = fully right ----
  reg [7:0]  pos = 8'd128;
  reg [15:0] step_cnt = 0;

  always @(posedge clk) begin
    if (is_analog) begin
      pos      <= joy[7:0];             // left stick X, 0x80 = centre
      step_cnt <= 0;
    end else if (step_cnt != 0) begin
      step_cnt <= step_cnt - 1'd1;
    end else if (!shift && (l1 ^ r1)) begin
      step_cnt <= KNOB_STEP;
      if (r1 && pos != 8'd255) pos <= pos + 1'd1;
      if (l1 && pos != 8'd0)   pos <= pos - 1'd1;
    end
  end

  // The console reads 0xFF fully left and 0x00 fully right (the same as
  // the MiSTer core's analog stick option)
  assign pot = ~pos;

endmodule


module input_map (
    input  wire        clk,
    input  wire [31:0] cont1_key, cont2_key, cont3_key, cont4_key,
    input  wire [31:0] cont1_joy, cont2_joy, cont3_joy, cont4_joy,
    input  wire        swap12,

    output wire [31:0] joya, joyb, joyc, joyd,
    output wire [7:0]  pda, pdb, pdc, pdd
);

  wire [31:0] p1, p2;
  wire [7:0]  k1, k2;

  pad_map m1 (.clk(clk), .key(cont1_key), .joy(cont1_joy), .j(p1),   .pot(k1));
  pad_map m2 (.clk(clk), .key(cont2_key), .joy(cont2_joy), .j(p2),   .pot(k2));
  pad_map m3 (.clk(clk), .key(cont3_key), .joy(cont3_joy), .j(joyc), .pot(pdc));
  pad_map m4 (.clk(clk), .key(cont4_key), .joy(cont4_joy), .j(joyd), .pot(pdd));

  assign joya = swap12 ? p2 : p1;
  assign joyb = swap12 ? p1 : p2;
  assign pda  = swap12 ? k2 : k1;
  assign pdb  = swap12 ? k1 : k2;

endmodule
