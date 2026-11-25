module tb_sync_fifo;
    localparam int DEPTH = 8;

    logic clk = 0, rst_n = 0, wr_en = 0, rd_en = 0, full, empty;
    logic [7:0] din = 0, dout;

    sync_fifo #(.DEPTH(DEPTH), .WIDTH(8)) dut (.*);
    always #5 clk = ~clk;

    // ---------------- Reference model + scoreboard ----------------
    logic [7:0] model[$];
    int errors = 0;
    int cov_wr_full = 0, cov_rd_empty = 0, cov_both_full = 0, cov_both_empty = 0;

    always @(posedge clk) if (rst_n) begin
        // 1. Flags must match the model (both describe the state before this edge)
        if (empty !== (model.size() == 0))     begin $display("[%0t] FAIL empty=%b model=%0d", $time, empty, model.size()); errors++; end
        if (full  !== (model.size() == DEPTH)) begin $display("[%0t] FAIL full=%b model=%0d",  $time, full,  model.size()); errors++; end
        if (wr_en && full)            cov_wr_full++;     // write attempted while full
        if (rd_en && empty)           cov_rd_empty++;    // read attempted while empty
        if (wr_en && rd_en && full)   cov_both_full++;
        if (wr_en && rd_en && empty)  cov_both_empty++;

        // 2. Accepted read: dout must be the oldest entry (FWFT)
        if (rd_en && !empty) begin
            automatic logic [7:0] exp;
            exp = model.pop_front();
            if (dout !== exp) begin $display("[%0t] FAIL dout=%h expected=%h", $time, dout, exp); errors++; end
        end

        // 3. Accepted write: the model stores it too
        if (wr_en && !full) model.push_back(din);
    end

    // ---------------- Assertion: never full and empty together ----------------
    assert property (@(posedge clk) disable iff (!rst_n) !(full && empty));

    // ---------------- Driver ----------------
    // One cycle of stimulus, applied on the falling edge
    task automatic cyc(input bit w, input bit r, input logic [7:0] d = '0);
        @(negedge clk);
        wr_en = w; rd_en = r; din = d;
    endtask

    task automatic do_reset();
        @(negedge clk); rst_n = 0; wr_en = 0; rd_en = 0;
        model.delete();                      // the model empties too
        @(negedge clk); rst_n = 1;
    endtask

    // ---------------- Tests ----------------
    initial begin
        $dumpfile("wave.vcd"); $dumpvars(0, tb_sync_fifo);
        do_reset();

        // T1: fill completely, then try one more write when full
        for (int i = 0; i < DEPTH; i++) cyc(1, 0, 8'hA0 + i);
        cyc(1, 0, 8'hFF);                    // must be ignored: 0xFF must never come out

        // T2: ...write the rest yourself (list below)
        cyc(1, 1, 8'hBA);

        //T3
        for (int i = 0; i < 7; i++) cyc(0, 1);
        cyc(0,1);

        //T4
        cyc(1,1, 8'hAA);

        //T5
        for (int i = 0; i < 3; i++) cyc(1, 0, 8'hA0 + i);
        cyc(1, 1, 8'hBA);

        //T6
        for (int i = 0; i < 6; i++) cyc(1, 1, 8'hB1 + i);

        //T7
        do_reset();
        cyc(1, 1, 8'hA0);
        cyc(0,1);

        // Random: 300 cycles, 50/50 reads and writes
        // repeat (300) cyc($urandom_range(0, 1), $urandom_range(0, 1), $urandom);
        repeat (150) cyc($urandom_range(0, 99) < 80, $urandom_range(0, 99) < 30, $urandom);   // 80% writes, 30% reads
        repeat (150) cyc($urandom_range(0, 99) < 30, $urandom_range(0, 99) < 80, $urandom);   // the reverse
        cyc(0, 0);                           // idle cycle so the last operation gets checked
        if (errors == 0) $display("PASS");
        else             $display("FAILED: %0d errors", errors);
        $display("Coverage: wr@full=%0d rd@empty=%0d both@full=%0d both@empty=%0d", cov_wr_full, cov_rd_empty, cov_both_full, cov_both_empty);
        $finish;
    end
endmodule 
