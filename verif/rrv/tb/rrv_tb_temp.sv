
module rrv_tb;

logic        Clk;
logic        Rst;

localparam TOP_IMEM_SIZE = 65536;
localparam TOP_DMEM_SIZE = 65536;
localparam D_MEM_SIZE    = 65536;
localparam D_MEM_OFFSET  = 65536;

logic  [7:0] IMem     [TOP_IMEM_SIZE-1 : 0];
logic  [7:0] NextIMem [TOP_IMEM_SIZE-1 : 0];
logic  [7:0] DMem     [D_MEM_SIZE + D_MEM_OFFSET - 1 : D_MEM_OFFSET];
logic  [7:0] NextDMem [D_MEM_SIZE + D_MEM_OFFSET - 1 : D_MEM_OFFSET];

`include "rrv_tasks.vh"

//=========================================
// Instantiating the rrv_top_core - DUT
//=========================================
    top top(
        .clk(Clk),
        .rst(Rst)
);

//=====================================
//      Reference model for RV32I
//=====================================
rv32i_ref
# (
    .I_MEM_LSB (0),
    .I_MEM_MSB (TOP_IMEM_SIZE-1),
    .D_MEM_LSB (D_MEM_OFFSET),
    .D_MEM_MSB (D_MEM_SIZE + D_MEM_OFFSET - 1)
)  rv32i_ref (
.clk  (Clk),
.rst  (Rst),
.run  (1'b1)
);


// ========================
// clock gen
// ========================
initial begin: clock_gen
    forever begin
        #5 Clk = 1'b0;
        #5 Clk = 1'b1;
    end //forever
end//initial clock_gen

// ========================
// reset generation
// ========================
initial begin: reset_gen
    Rst = 1'b1;
#40 Rst = 1'b0;
end: reset_gen

//always_ff @(posedge Clk) begin
//   IMem <= NextIMem;
//   DMem <= NextDMem;
//end

string  test_name;
integer file;
integer trk_gpr;

localparam DELAY = 5;
localparam N     = 100;  
integer    i;

initial begin: test_seq
    if ($value$plusargs ("STRING=%s", test_name))
        $display("STRING value %s", test_name);

    //======================================
    //load the program to the TB
    //======================================
    $readmemh({"../../../target/rrv/tests/",test_name,"/gcc_files/inst_mem.sv"} , IMem);
    //$readmemh({"../../../target/rrv/tests/",test_name,"/gcc_files/inst_mem.sv"} , NextIMem);
    force top.fetch_module.inst_ram_module.inst_ram = IMem;

    // loading the reference model:
    $readmemh({"../../../target/rrv/tests/",test_name,"/gcc_files/inst_mem.sv"} , IMem);
    //$readmemh({"../../../target/rrv/tests/",test_name,"/gcc_files/data_mem.sv"} , DMem);
    force rv32i_ref.imem = IMem; //backdoor to reference model memory
    //force rv32i_ref.dmem = DMem; //backdoor to reference model memory
    //#10;
    //release rv32i_ref.imem;
    //release rv32i_ref.dmem;


    //======================================
    // open the file for tracking the GPR
    //======================================
    trk_gpr = $fopen({"../../../target/rrv/tests/",test_name,"/trk_gpr.log"},"w");
    
    $fdisplay(trk_gpr, "GPR TRACKER");
    $fdisplay(trk_gpr, "-----------");
    for(i=0; i<N;i=i+1) begin
        #(2*DELAY);
        track_gpr();
        show_gpr();
    end 

    $fclose(trk_gpr);              

    //file = $fopen({"../../../target/rrv/tests/",test_name,"/gcc_files/data_mem.sv"}, "r");
    //if (file) begin
    //    $fclose(file);
    //    $readmemh({"../../../target/big_core/tests/",test_name,"/gcc_files/data_mem.sv"} , DMem);
    //    $readmemh({"../../../target/big_core/tests/",test_name,"/gcc_files/data_mem.sv"} , NextDMem);
    //    force top.mem_stage_module.data_ram.data_ram = DMem;
    //    #10
    //    release top.mem_stage_module.data_ram.data_ram;
    //end

    //#10000;
    //$error(" Timeout \n===================\n test %s ended timeout \n=====================", test_name);
    #100000
    //========================
    // before the end on tets, run the Data integrity check
    //========================
    di_register_write();
    //========================

    $finish;

end // test_seq

initial begin : used_for_debug_and_test
    fork
        get_rf_write();
        get_ref_rf_write();
    join
end
integer j, k;
int NUM = 32;

task track_gpr(); begin
    $fwrite(trk_gpr, "GPR = {");
    for(j=0; j<NUM-1; j=j+1) begin
        $fwrite(trk_gpr, "%1h, ", top.decode_module.gpr_module.gpr_mem[j]);
    end
    $fwrite(trk_gpr, "%1h}", top.decode_module.gpr_module.gpr_mem[j]);
    $fdisplay(trk_gpr, "    time is: %1t[ps]\n", $time());
end
endtask

task show_gpr(); begin
    $write("GPR = {");
    for(k=0; k<NUM-1; k=k+1) begin
        $write("%1h, ", top.decode_module.gpr_module.gpr_mem[k]);
    end
    $write("%1h}", top.decode_module.gpr_module.gpr_mem[k]);
    $display("    time is: %1t[ps]", $time());
end
endtask




endmodule //rrv_tb_core