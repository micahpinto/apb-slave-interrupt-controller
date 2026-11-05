// apb_irq_ctrl_tb.sv
// Self-checking testbench for apb_irq_ctrl.
// Acts as the CPU on the APB bus and drives the four interrupt inputs.
`timescale 1ns/1ps
module apb_irq_ctrl_tb;

  logic        r_Clk    = 0;
  logic        r_Rst_n  = 0;
  logic        r_Sel    = 0;
  logic        r_Enable = 0;
  logic        r_Write  = 0;
  logic [7:0]  r_Addr   = 0;
  logic [31:0] r_Wdata  = 0;
  logic [3:0]  r_Irq    = 0;

  wire  [31:0] w_Rdata;
  wire         w_Ready;
  wire         w_Slverr;
  wire         w_Irq_Out;

  apb_irq_ctrl dut (
    .i_PCLK   (r_Clk),
    .i_PRESETn(r_Rst_n),
    .i_PSEL   (r_Sel),
    .i_PENABLE(r_Enable),
    .i_PWRITE (r_Write),
    .i_PADDR  (r_Addr),
    .i_PWDATA (r_Wdata),
    .o_PRDATA (w_Rdata),
    .o_PREADY (w_Ready),
    .o_PSLVERR(w_Slverr),
    .i_Irq    (r_Irq),
    .o_Irq    (w_Irq_Out)
  );

  always #5 r_Clk = ~r_Clk;   // 100 MHz

  localparam logic [7:0] ADDR_ENABLE = 8'h00;
  localparam logic [7:0] ADDR_STATUS = 8'h04;
  localparam logic [7:0] ADDR_CLEAR  = 8'h08;
  localparam logic [7:0] ADDR_ACTIVE = 8'h0C;

  int errors = 0;

  // ---------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------
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

  task automatic apb_write(input  logic [7:0]  addr,
                           input  logic [31:0] data,
                           output logic        err);
    @(posedge r_Clk);                    // SETUP
    r_Sel    <= 1;
    r_Enable <= 0;
    r_Write  <= 1;
    r_Addr   <= addr;
    r_Wdata  <= data;
    @(posedge r_Clk);                    // ACCESS
    r_Enable <= 1;
    @(posedge r_Clk);
    while (!w_Ready) @(posedge r_Clk);
    err = w_Slverr;
    r_Sel    <= 0;
    r_Enable <= 0;
  endtask

  task automatic apb_read(input  logic [7:0]  addr,
                          output logic [31:0] data,
                          output logic        err);
    @(posedge r_Clk);                    // SETUP
    r_Sel    <= 1;
    r_Enable <= 0;
    r_Write  <= 0;
    r_Addr   <= addr;
    @(posedge r_Clk);                    // ACCESS
    r_Enable <= 1;
    @(posedge r_Clk);
    while (!w_Ready) @(posedge r_Clk);
    data = w_Rdata;
    err  = w_Slverr;
    r_Sel    <= 0;
    r_Enable <= 0;
  endtask

  // Bus transfer meant for another peripheral (PSEL = 0)
  task automatic other_transfer(input  logic        write,
                                input  logic [7:0]  addr,
                                input  logic [31:0] data,
                                output logic [31:0] our_rdata);
    @(posedge r_Clk);
    r_Sel    <= 0;
    r_Enable <= 0;
    r_Write  <= write;
    r_Addr   <= addr;
    r_Wdata  <= data;
    @(posedge r_Clk);
    r_Enable <= 1;
    @(posedge r_Clk);
    our_rdata = w_Rdata;
    r_Enable <= 0;
  endtask

  // Set the chosen interrupt inputs to 1 for one clock
  task automatic pulse_irq(input logic [3:0] sources);
    @(posedge r_Clk);
    r_Irq <= sources;
    @(posedge r_Clk);
    r_Irq <= 4'b0000;
  endtask

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  logic [31:0] d;
  logic        e;

  initial begin
    repeat (3) @(posedge r_Clk);
    r_Rst_n <= 1;

    // Test 1: reset values
    $display("--- Test 1: reset values");
    apb_read(ADDR_ENABLE, d, e);  check("ENABLE", d, 0);
    apb_read(ADDR_STATUS, d, e);  check("STATUS", d, 0);
    apb_read(ADDR_CLEAR,  d, e);  check("CLEAR",  d, 0);
    apb_read(ADDR_ACTIVE, d, e);  check("ACTIVE", d, 0);
    check("o_Irq", w_Irq_Out, 0);

    // Test 2: a 1-clock request is remembered; a disabled interrupt does not raise o_Irq
    $display("--- Test 2: request is remembered");
    pulse_irq(4'b0100);
    repeat (5) @(posedge r_Clk);
    apb_read(ADDR_STATUS, d, e);  check("STATUS", d, 4'b0100);
    check("o_Irq masked", w_Irq_Out, 0);
    apb_write(ADDR_CLEAR, 4'b1111, e);

    // Test 3: CLEAR only removes the bits written as 1
    $display("--- Test 3: clear one bit");
    pulse_irq(4'b0110);
    apb_write(ADDR_CLEAR, 4'b0010, e);
    check("write CLEAR err", e, 0);
    apb_read(ADDR_STATUS, d, e);  check("STATUS after clear", d, 4'b0100);
    apb_write(ADDR_CLEAR, 4'b1111, e);

    // Test 4: enabling a waiting interrupt raises o_Irq
    $display("--- Test 4: mask");
    pulse_irq(4'b1000);
    apb_read(ADDR_STATUS, d, e);  check("STATUS", d, 4'b1000);
    check("o_Irq before enable", w_Irq_Out, 0);
    apb_write(ADDR_ENABLE, 4'b1000, e);
    #1;                                  // wait 1 ns so the new value is visible
    check("o_Irq after enable", w_Irq_Out, 1);
    apb_write(ADDR_CLEAR, 4'b1111, e);
    #1;
    check("o_Irq after clear", w_Irq_Out, 0);

    // Test 5: priority, lowest number first
    $display("--- Test 5: priority");
    apb_write(ADDR_ENABLE, 4'b1111, e);
    pulse_irq(4'b1010);
    apb_read(ADDR_ACTIVE, d, e);  check("ACTIVE src1", d, 32'h8000_0001);
    apb_write(ADDR_CLEAR, 4'b0010, e);
    apb_read(ADDR_ACTIVE, d, e);  check("ACTIVE src3", d, 32'h8000_0003);
    apb_write(ADDR_CLEAR, 4'b1000, e);
    apb_read(ADDR_ACTIVE, d, e);  check("ACTIVE none", d, 32'h0000_0000);
    check("o_Irq none", w_Irq_Out, 0);

    // Test 6: error responses
    $display("--- Test 6: errors");
    apb_write(ADDR_STATUS, 4'b1111, e);  check("write STATUS err", e, 1);
    apb_read (ADDR_CLEAR,  d, e);        check("read CLEAR err",   e, 0);
                                         check("read CLEAR data",  d, 0);
    apb_write(8'h10, 4'b1111, e);        check("write 0x10 err",   e, 1);

    // Test 7: unused bits read 0, more error cases
    $display("--- Test 7: unused bits, more errors");
    apb_write(ADDR_ENABLE, 32'hFFFF_FFFF, e);
    apb_read (ADDR_ENABLE, d, e);        check("ENABLE unused bits", d, 32'h0000_000F);
    apb_write(ADDR_ACTIVE, 4'b0001, e);  check("write ACTIVE err",   e, 1);
    apb_read (8'h06, d, e);              check("read 0x06 err",      e, 1);

    // Test 8: clear several bits in one write
    $display("--- Test 8: clear several bits");
    pulse_irq(4'b1111);
    apb_read (ADDR_STATUS, d, e);        check("STATUS all", d, 4'b1111);
    apb_write(ADDR_CLEAR, 4'b1111, e);
    apb_read (ADDR_STATUS, d, e);        check("STATUS none", d, 0);

    // Test 9: traffic for another peripheral (PSEL = 0) changes nothing
    $display("--- Test 9: PSEL = 0 traffic");
    pulse_irq(4'b0001);
    other_transfer(1, ADDR_ENABLE, 32'h0, d);  check("PRDATA other write", d, 0);
    other_transfer(1, ADDR_CLEAR,  32'hF, d);  check("PRDATA other clear", d, 0);
    apb_read(ADDR_ENABLE, d, e);               check("ENABLE unchanged", d, 32'h0000_000F);
    apb_read(ADDR_STATUS, d, e);               check("STATUS unchanged", d, 4'b0001);

    // Test 10: reset in the middle of the test
    $display("--- Test 10: reset");
    @(posedge r_Clk);
    r_Rst_n <= 0;
    @(posedge r_Clk);
    r_Rst_n <= 1;
    apb_read(ADDR_ENABLE, d, e);  check("ENABLE after reset", d, 0);
    apb_read(ADDR_STATUS, d, e);  check("STATUS after reset", d, 0);
    apb_read(ADDR_ACTIVE, d, e);  check("ACTIVE after reset", d, 0);
    check("o_Irq after reset", w_Irq_Out, 0);

    $display("==========================================");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

endmodule