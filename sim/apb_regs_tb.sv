// self-checking testbench for apb_regs 
// The testbench plays the APB manager (the bridge).
`timescale 1ns/1ps
module apb_regs_tb;

  //signals the testbench DRIVES
  logic        r_Clk    = 0;
  logic        r_Rst_n  = 0;      // reset active (low) at the start
  logic        r_Sel    = 0;
  logic        r_Enable = 0;
  logic        r_Write  = 0;
  logic [7:0]  r_Addr   = 0;
  logic [31:0] r_Wdata  = 0;

  //signals the DUT drives
  wire  [31:0] w_Rdata;
  wire         w_Ready;
  wire         w_Slverr;

  //design under test
  apb_regs dut (
    .i_PCLK   (r_Clk),
    .i_PRESETn(r_Rst_n),
    .i_PSEL   (r_Sel),
    .i_PENABLE(r_Enable),
    .i_PWRITE (r_Write),
    .i_PADDR  (r_Addr),
    .i_PWDATA (r_Wdata),
    .o_PRDATA (w_Rdata),
    .o_PREADY (w_Ready),
    .o_PSLVERR(w_Slverr)
  );

  //clock: 10 ns period = 100 MHz
  always #5 r_Clk = ~r_Clk;

  // ---- register addresses and values ----
  localparam logic [7:0]  ADDR_CTRL  = 8'h00;
  localparam logic [7:0]  ADDR_DATA0 = 8'h04;
  localparam logic [7:0]  ADDR_DATA1 = 8'h08;
  localparam logic [7:0]  ADDR_ID    = 8'h0C;
  localparam logic [31:0] ID_VALUE   = 32'hA9B0_0001;

  int errors = 0;   // counts every failed check

  // ================= tasks =================

  // compare and count
  task automatic check(input string       name,
                       input logic [31:0] got,
                       input logic [31:0] expected);
    if (got === expected)
      $display("PASS  %s = %h", name, got);
    else begin
      $display("FAIL  %s = %h, expected %h   (time %0t)", name, got, expected, $time);
      errors++;
    end
  endtask

  // APB write: SETUP -> ACCESS -> wait for PREADY
  task automatic apb_write(input  logic [7:0]  addr,
                           input  logic [31:0] data,
                           output logic        err);
    @(posedge r_Clk);                   // SETUP
    r_Sel    <= 1;
    r_Enable <= 0;
    r_Write  <= 1;
    r_Addr   <= addr;
    r_Wdata  <= data;
    @(posedge r_Clk);                   // ACCESS
    r_Enable <= 1;
    @(posedge r_Clk);                   // end of ACCESS (if PREADY = 1)
    while (!w_Ready) @(posedge r_Clk);  // wait states
    err = w_Slverr;
    r_Sel    <= 0;                      // back to IDLE
    r_Enable <= 0;
  endtask

  // APB read: same, PWRITE = 0, PRDATA captured at the end
  task automatic apb_read(input  logic [7:0]  addr,
                          output logic [31:0] data,
                          output logic        err);
    @(posedge r_Clk);                   // SETUP
    r_Sel    <= 1;
    r_Enable <= 0;
    r_Write  <= 0;
    r_Addr   <= addr;
    @(posedge r_Clk);                   // ACCESS
    r_Enable <= 1;
    @(posedge r_Clk);                   // end of ACCESS
    while (!w_Ready) @(posedge r_Clk);
    data = w_Rdata;
    err  = w_Slverr;
    r_Sel    <= 0;                      // back to IDLE
    r_Enable <= 0;
  endtask

  // A transfer meant for ANOTHER peripheral: same wires, but our PSEL stays 0.
  // Returns what our PRDATA showed during its ACCESS cycle (must be 0).
  task automatic other_transfer(input  logic        write,
                                input  logic [7:0]  addr,
                                input  logic [31:0] data,
                                output logic [31:0] our_rdata);
    @(posedge r_Clk);                   // SETUP (for the other peripheral)
    r_Sel    <= 0;                      // NOT us
    r_Enable <= 0;
    r_Write  <= write;
    r_Addr   <= addr;
    r_Wdata  <= data;
    @(posedge r_Clk);                   // ACCESS
    r_Enable <= 1;
    @(posedge r_Clk);                   // end of ACCESS
    our_rdata = w_Rdata;
    r_Enable <= 0;
  endtask

  // ================= the tests =================
  logic [31:0] d;   // data read back
  logic        e;   // PSLVERR

  initial begin
    repeat (3) @(posedge r_Clk);        // hold reset for 3 clocks
    r_Rst_n <= 1;                       // release reset

    //Test 1: ID after reset
    $display("--- Test 1: ID after reset");
    apb_read(ADDR_ID, d, e);          check("ID", d, ID_VALUE);
                                      check("ID err", e, 0);

    //Test 2: reset values
    $display("--- Test 2: reset values");
    apb_read(ADDR_CTRL,  d, e);       check("CTRL",  d, 0);  check("CTRL err",  e, 0);
    apb_read(ADDR_DATA0, d, e);       check("DATA0", d, 0);  check("DATA0 err", e, 0);
    apb_read(ADDR_DATA1, d, e);       check("DATA1", d, 0);  check("DATA1 err", e, 0);

    //Test 3: write and read back each RW register
    $display("--- Test 3: write / read back");
    apb_write(ADDR_CTRL,  32'h1111_0000, e);  check("write CTRL err",  e, 0);
    apb_write(ADDR_DATA0, 32'hCAFE_0001, e);  check("write DATA0 err", e, 0);
    apb_write(ADDR_DATA1, 32'h5A5A_A5A5, e);  check("write DATA1 err", e, 0);
    apb_read (ADDR_CTRL,  d, e);              check("CTRL",  d, 32'h1111_0000);
    apb_read (ADDR_DATA0, d, e);              check("DATA0", d, 32'hCAFE_0001);
    apb_read (ADDR_DATA1, d, e);              check("DATA1", d, 32'h5A5A_A5A5);

    //Test 4: a read changes nothing
    $display("--- Test 4: read twice");
    apb_read(ADDR_DATA0, d, e);       check("DATA0 read 1", d, 32'hCAFE_0001);
    apb_read(ADDR_DATA0, d, e);       check("DATA0 read 2", d, 32'hCAFE_0001);

    //Test 5: ID is read-only
    $display("--- Test 5: write to ID");
    apb_write(ADDR_ID, 32'hFFFF_FFFF, e);  check("write ID err", e, 1);
    apb_read (ADDR_ID, d, e);              check("ID unchanged", d, ID_VALUE);
                                           check("read ID err",  e, 0);

    //Test 6: unaligned addresses
    $display("--- Test 6: unaligned addresses");
    apb_read (8'h06, d, e);                check("read 0x06 err",  e, 1);
    apb_write(8'h06, 32'hDEAD_0006, e);    check("write 0x06 err", e, 1);
    apb_write(8'h0A, 32'hDEAD_000A, e);    check("write 0x0A err", e, 1);
    apb_read (ADDR_DATA0, d, e);           check("DATA0 untouched", d, 32'hCAFE_0001);
    apb_read (ADDR_DATA1, d, e);           check("DATA1 untouched", d, 32'h5A5A_A5A5);

    //Test 7: out-of-range addresses
    $display("--- Test 7: out-of-range addresses");
    apb_read (8'h10, d, e);                check("read 0x10 err",  e, 1);
    apb_write(8'h14, 32'hDEAD_0014, e);    check("write 0x14 err", e, 1);
    apb_read (ADDR_DATA0, d, e);           check("DATA0 untouched by 0x14", d, 32'hCAFE_0001);

    //Test 8: traffic for another peripheral (our PSEL = 0)
    $display("--- Test 8: PSEL = 0 traffic");
    other_transfer(1, ADDR_CTRL, 32'hBEEF_BEEF, d);  check("our PRDATA during other write", d, 0);
    other_transfer(0, ADDR_DATA0, 0, d);             check("our PRDATA during other read",  d, 0);
    apb_read(ADDR_CTRL, d, e);                       check("CTRL unchanged", d, 32'h1111_0000);

    //Test 9: back-door check (look inside the DUT)
    $display("--- Test 9: back-door");
    check("back-door CTRL",  dut.r_Regs[0], 32'h1111_0000);
    check("back-door DATA0", dut.r_Regs[1], 32'hCAFE_0001);
    check("back-door DATA1", dut.r_Regs[2], 32'h5A5A_A5A5);

    //Test 10: reset in the middle
    $display("--- Test 10: reset again");
    @(posedge r_Clk);
    r_Rst_n <= 0;
    @(posedge r_Clk);
    r_Rst_n <= 1;
    apb_read(ADDR_CTRL,  d, e);       check("CTRL after reset",  d, 0);
    apb_read(ADDR_DATA0, d, e);       check("DATA0 after reset", d, 0);
    apb_read(ADDR_DATA1, d, e);       check("DATA1 after reset", d, 0);
    apb_read(ADDR_ID,    d, e);       check("ID after reset",    d, ID_VALUE);

    //summary
    $display("==========================================");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

endmodule