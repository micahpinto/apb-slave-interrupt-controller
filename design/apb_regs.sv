// apb_regs.sv : APB slave with a small register file 
//
// Register map (32-bit registers, byte addresses):
//   0x00  CTRL   read/write   reset 0
//   0x04  DATA0  read/write   reset 0
//   0x08  DATA1  read/write   reset 0
//   0x0C  ID     read-only    0xA9B0_0001 (fixed)
//   other        error: PSLVERR = 1 (out of range, or not aligned to 4 bytes)
//   write to ID  error: PSLVERR = 1, nothing changes
// No wait states: PREADY is always 1.

module apb_regs (
  input  logic        i_PCLK,
  input  logic        i_PRESETn,   // active low, asynchronous
  input  logic        i_PSEL,
  input  logic        i_PENABLE,
  input  logic        i_PWRITE,
  input  logic [7:0]  i_PADDR,
  input  logic [31:0] i_PWDATA,
  output logic [31:0] o_PRDATA,
  output logic        o_PREADY,
  output logic        o_PSLVERR
);

  localparam logic [31:0] ID_VALUE = 32'hA9B0_0001;

  //decode
  wire       w_Access   = i_PSEL & i_PENABLE;           // ACCESS phase
  wire [1:0] w_Index    = i_PADDR[3:2];                 // which register
  wire       w_Bad_Addr = (|i_PADDR[7:4])               // 0x10 or above
                        | (i_PADDR[1:0] != 2'b00);      // not aligned
  wire       w_Ro_Write = i_PWRITE & (w_Index == 2'd3); // write to ID
  wire       w_Error    = w_Bad_Addr | w_Ro_Write;

  wire       w_Wr_En    = w_Access &  i_PWRITE & ~w_Error;  // good write
  wire       w_Rd_En    = w_Access & ~i_PWRITE & ~w_Error;  // good read

  assign o_PREADY  = 1'b1;               // no wait states
  assign o_PSLVERR = w_Access & w_Error; // only in the final cycle

  //registers (write)
  logic [31:0] r_Regs [0:2];   // [0]=CTRL, [1]=DATA0, [2]=DATA1

  always_ff @(posedge i_PCLK or negedge i_PRESETn) begin
    if (!i_PRESETn) begin
      r_Regs[0] <= 32'h0;
      r_Regs[1] <= 32'h0;
      r_Regs[2] <= 32'h0;
    end else if (w_Wr_En) begin
      r_Regs[w_Index] <= i_PWDATA;   // index 3 never gets here (read-only)
    end
  end

  //read mux
  always_comb begin
    o_PRDATA = 32'h0;                 // default: no latch
    if (w_Rd_En) begin
      case (w_Index)
        2'd0: o_PRDATA = r_Regs[0];   // CTRL
        2'd1: o_PRDATA = r_Regs[1];   // DATA0
        2'd2: o_PRDATA = r_Regs[2];   // DATA1
        2'd3: o_PRDATA = ID_VALUE;    // ID
      endcase
    end
  end

endmodule