//
// Data slot loader for the Analogue Pocket (BIOS or cartridge)
//
// The Pocket writes a file over the APF bridge (clk_74a domain) as 32 bit
// big endian words at REGION << 28 + offset. They are kept in an 8 KB dual
// clock RAM that the console reads byte by byte in its own clock domain.
//
// The RAM is four byte wide RAMs, one per byte lane, so a whole word is
// written at once on the bridge side. The console side behaves like the
// MiSTer core's ROM: the address is registered and the byte appears on
// the next clock. Bytes past the end of the file read as 0, so nothing is
// left over from a bigger file loaded earlier.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module slot_loader #(
    parameter [3:0] REGION = 4'h1
) (
    input  wire        clk_74a,
    input  wire        reset_n,        // APF reset (low while the Pocket loads)

    input  wire        bridge_wr,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,

    output reg  [11:0] size_words = 0, // 32 bit words loaded (0..2048)

    input  wire        clk_sys,
    input  wire [11:0] size_words_sys, // size_words synchronised to clk_sys
    input  wire [12:0] rd_addr,
    output wire [7:0]  rd_data
);

  reg [7:0] lane0 [0:2047];
  reg [7:0] lane1 [0:2047];
  reg [7:0] lane2 [0:2047];
  reg [7:0] lane3 [0:2047];

  reg prev_wr      = 0;
  reg prev_reset_n = 1;

  wire        hit  = (bridge_addr[31:28] == REGION) && (bridge_addr[27:13] == 15'd0);
  wire [10:0] widx = bridge_addr[12:2];

  always @(posedge clk_74a) begin
    prev_wr      <= bridge_wr;
    prev_reset_n <= reset_n;

    // APF holds the core in reset while it loads the data slots, so a new
    // load starts on the falling edge of reset_n.
    if (prev_reset_n && ~reset_n) size_words <= 0;

    if (bridge_wr && ~prev_wr && hit) begin
      if ({1'b0, widx} + 12'd1 > size_words) size_words <= {1'b0, widx} + 12'd1;
    end
  end

  // APF delivers file bytes big endian: the first byte is in [31:24]
  always @(posedge clk_74a) begin
    if (bridge_wr && ~prev_wr && hit) begin
      lane0[widx] <= bridge_wr_data[31:24];
      lane1[widx] <= bridge_wr_data[23:16];
      lane2[widx] <= bridge_wr_data[15:8];
      lane3[widx] <= bridge_wr_data[7:0];
    end
  end

  reg [7:0] q0, q1, q2, q3;
  reg [1:0] lane_sel;
  reg       in_file;

  always @(posedge clk_sys) begin
    q0       <= lane0[rd_addr[12:2]];
    q1       <= lane1[rd_addr[12:2]];
    q2       <= lane2[rd_addr[12:2]];
    q3       <= lane3[rd_addr[12:2]];
    lane_sel <= rd_addr[1:0];
    in_file  <= ({1'b0, rd_addr[12:2]} < size_words_sys);
  end

  assign rd_data = !in_file        ? 8'h00 :
                   (lane_sel == 2'd0) ? q0 :
                   (lane_sel == 2'd1) ? q1 :
                   (lane_sel == 2'd2) ? q2 : q3;

endmodule
