// Core -> Cache request
typedef struct packed {
    logic [4:0]   RegDst;   //reg destination
    logic [31:0]  Data;    
    logic [31:0]  Pc;
    logic [31:0]  cur_time;
} t_rf_write_history ;

t_rf_write_history rf_write_history[$];
t_rf_write_history rf_cur_write;
t_rf_write_history ref_rf_write_history[$];
t_rf_write_history ref_rf_cur_write;

logic [31:0] PcQ102H, PcQ103H, PcQ104H;

assign PcQ102H = top.execution_module.pc;
always_ff @(posedge Clk) PcQ103H <= PcQ102H;
always_ff @(posedge Clk) PcQ104H <= PcQ103H;

logic RegWrEnQ104H;
logic [4:0]  RegDstQ104H;
logic [31:0] RegWrDataQ104H;

assign RegWrEnQ104H   = top.decode_module.gpr_we_wb;
assign RegDstQ104H    = top.decode_module.addr_rd_wb;
assign RegWrDataQ104H = top.decode_module.rd_in_wb;

task get_rf_write();
$display("get_rf_write start");
fork forever begin 
    @(posedge Clk) begin
        if (RegWrEnQ104H && (RegDstQ104H!=5'b0)) begin
            rf_cur_write.RegDst    = RegDstQ104H;
            rf_cur_write.Data      = RegWrDataQ104H;
            rf_cur_write.Pc        = PcQ104H;
            rf_cur_write.cur_time  = $time;
            rf_write_history.push_back(rf_cur_write);
    // $display("rf_cur_write = %p", rf_cur_write);
        end
    end
end
join_none
endtask

task get_ref_rf_write();
fork forever begin 
    @(posedge Clk) begin
        if (rv32i_ref.reg_wr_en) begin
            ref_rf_cur_write.RegDst = rv32i_ref.rd;
            ref_rf_cur_write.Data   = rv32i_ref.next_regfile[rv32i_ref.rd];
            ref_rf_cur_write.Pc     = rv32i_ref.pc;
            ref_rf_cur_write.cur_time   = $time;
            if (rv32i_ref.rd != 5'b0) begin
                ref_rf_write_history.push_back(ref_rf_cur_write);
                // $display("ref_rf_cur_write = %p", ref_rf_cur_write);
            end
        end
    end
end
join_none
endtask


string msg = "Data integrity test passed"; // default

task di_register_write();
$display("ref_rf_write_history size = %0d", ref_rf_write_history.size());
$display("rf_write_history size     = %0d", rf_write_history.size());
foreach(rf_write_history[i])begin
    if ((ref_rf_write_history[i].RegDst == rf_write_history[i].RegDst ) && 
        (ref_rf_write_history[i].Data   == rf_write_history[i].Data   ) )
    begin
        $display(" >> rf_write_history[%0d] Match: time: %0d, PC: %8h, RegDsd: %d, Data: %h", i, rf_write_history[i].cur_time,
                                                                                                 rf_write_history[i].Pc,
                                                                                                 rf_write_history[i].RegDst,
                                                                                                 rf_write_history[i].Data);
        //ref_rf_write_history.delete(i);
        //rf_write_history.delete(i);
    end else begin
        $display(" >> rf_write_history[%0d] Mismatch!!", i);
        $error("ERROR: rf_write_history mismatch");
        $display("      ref_rf_write_history[%0d] =   {time: %0d, Pc: %8h, RegDst: %d, Data: %h}", i, ref_rf_write_history[i].cur_time, ref_rf_write_history[i].Pc, ref_rf_write_history[i].RegDst, ref_rf_write_history[i].Data);
        $display("      rf_write_history    [%0d] =   {time: %0d, Pc: %8h, RegDst: %d, Data: %h}", i, rf_write_history[i].cur_time    , rf_write_history[i].Pc    , rf_write_history[i].RegDst    , rf_write_history[i].Data    );
        msg = "Data integrity test failed - rf_write_history mismatch";
    end
end

if(ref_rf_write_history.size() != rf_write_history.size()) begin
    $error("ERROR: rf_write_history size mismatch");
    msg = "Data integrity test failed - rf_write_history size mismatch";
end else begin
    $display("rf_write_history size match");
end
$display("Data Integrity final status: %s", msg);
$display("===============================\n");
//TODO - review why the below code is not working (history not empty)
//if(ref_rf_write_history.size() != 0) begin
//    $error("ERROR: rf_write_history not empty");
//end else begin
//    $display("rf_write_history size match");
//end

endtask


