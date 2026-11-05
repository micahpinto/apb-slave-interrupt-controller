// apb_irq_ctrl.sv
// Interrupt controller, set up and read by the CPU over the APB bus.
// 4 interrupt sources, fixed priority (source 0 highest).
//
// Register map:
//   0x00  ENABLE  RW   [3:0]   1 = interrupt allowed, reset 0
//   0x04  STATUS  RO   [3:0]   interrupts waiting to be handled, reset 0
//   0x08  CLEAR   WO   [3:0]   write 1 to clear a waiting interrupt, reads 0
//   0x0C  ACTIVE  RO   [31]    VALID: 1 if an allowed interrupt is waiting
//                      [1:0]   number of the interrupt to handle first
// Bad addresses and writes to read-only registers return PSLVERR = 1.
// Unused bits read as 0. PREADY is always 1 (no wait states).

module apb_irq_ctrl (
  input  logic        i_PCLK,
  input  logic        i_PRESETn,
  input  logic        i_PSEL,
  input  logic        i_PENABLE,
  input  logic        i_PWRITE,
  input  logic [7:0]  i_PADDR,
  input  logic [31:0] i_PWDATA,
  output logic [31:0] o_PRDATA,
  output logic        o_PREADY,
  output logic        o_PSLVERR,
  input  logic [3:0]  i_Irq,
  output logic        o_Irq
);

  // Address decode and error check
  wire       w_Access   = i_PSEL & i_PENABLE;
  wire [1:0] w_Index    = i_PADDR[3:2];
  wire       w_Bad_Addr = (|i_PADDR[7:4]) | (i_PADDR[1:0] != 2'b00);
  wire       w_Ro_Write = i_PWRITE & ((w_Index == 2'd1) | (w_Index == 2'd3));
  wire       w_Error    = w_Bad_Addr | w_Ro_Write;

  wire       w_Wr_En    = w_Access &  i_PWRITE & ~w_Error;
  wire       w_Rd_En    = w_Access & ~i_PWRITE & ~w_Error;

  assign o_PREADY  = 1'b1;
  assign o_PSLVERR = w_Access & w_Error;

  // Registers
  logic [3:0] r_Enable;
  logic [3:0] r_Pending;

  // CLEAR is not stored; it is only used during the write
  wire [3:0] w_Clear = (w_Wr_En && w_Index == 2'd2) ? i_PWDATA[3:0] : 4'b0000;

  always_ff @(posedge i_PCLK or negedge i_PRESETn) begin
    if (!i_PRESETn) begin
      r_Enable  <= 4'b0000;
      r_Pending <= 4'b0000;
    end else begin
      if (w_Wr_En && w_Index == 2'd0)
        r_Enable <= i_PWDATA[3:0];
      r_Pending <= (r_Pending | i_Irq) & ~w_Clear;   // add new requests, remove cleared ones
    end
  end

  // Priority: the lowest interrupt number wins
  wire [3:0] w_Live = r_Pending & r_Enable;

  logic       w_Valid;
  logic [1:0] w_Id;

  always_comb begin
    w_Valid = 1'b1;
    w_Id    = 2'd0;
    if      (w_Live[0]) w_Id = 2'd0;
    else if (w_Live[1]) w_Id = 2'd1;
    else if (w_Live[2]) w_Id = 2'd2;
    else if (w_Live[3]) w_Id = 2'd3;
    else                w_Valid = 1'b0;
  end

  assign o_Irq = |w_Live;

  // Read data
  always_comb begin
    o_PRDATA = 32'h0;
    if (w_Rd_En) begin
      case (w_Index)
        2'd0: o_PRDATA = {28'h0, r_Enable};
        2'd1: o_PRDATA = {28'h0, r_Pending};
        2'd2: o_PRDATA = 32'h0;
        2'd3: o_PRDATA = {w_Valid, 29'h0, w_Id};
      endcase
    end
  end

endmodule