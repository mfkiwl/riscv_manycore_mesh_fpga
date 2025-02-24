//-----------------------------------------------------------------------------
// Title            : 
// Project          : 
//-----------------------------------------------------------------------------
// File             : <TODO>
// Original Author  : 
// Code Owner       : 
// Created          : 
//-----------------------------------------------------------------------------
// Description : 
//
//
//-----------------------------------------------------------------------------
`include "macros.sv"

module  i_cache_tq 
    import i_cache_param_pkg::*;  
(
    input   logic           clk,        
    input   logic           rst,        
    //core Interface
    input   var t_req       pre_core2cache_req,
    output  logic           ready,
    output  t_rd_rsp        cache2core_rsp,
    //FM Interface
    input   var t_fm_rd_rsp fm2cache_rd_rsp,
    //Pipe Interface
    output  t_lu_req           pipe_lu_req_q1,
    input   var t_early_lu_rsp pipe_early_lu_rsp_q2,
    input   var t_lu_rsp       pipe_lu_rsp_q3
);
t_req                         core2cache_req;
t_req                         reissue_req;
t_tq_state [NUM_TQ_ENTRY-1:0] tq_state;
t_tq_state [NUM_TQ_ENTRY-1:0] next_tq_state;

logic stall;
logic [NUM_TQ_ENTRY-1:0] rd_req_hit_mb;
logic any_rd_hit_mb;

logic [NUM_TQ_ENTRY-1:0] free_entries;
logic [NUM_TQ_ENTRY-1:0] allocate_entry;
logic [NUM_TQ_ENTRY-1:0] first_free;
logic [NUM_TQ_ENTRY-1:0] fill_entries;
logic [NUM_TQ_ENTRY-1:0] first_fill;

logic    [NUM_TQ_ENTRY-1:0] en_tq_merge_buffer_data; 
logic    [NUM_TQ_ENTRY-1:0] en_tq_cl_address; 
logic    [NUM_TQ_ENTRY-1:0] en_tq_cl_word_offset; 
logic    [NUM_TQ_ENTRY-1:0] en_tq_rd_indication; 
logic    [NUM_TQ_ENTRY-1:0] en_tq_reg_id; 

logic        [NUM_TQ_ENTRY-1:0][NUM_WORDS_IN_CL-1:0]  tq_merge_buffer_e_modified; 
t_cl         [NUM_TQ_ENTRY-1:0] tq_merge_buffer_data; 
t_cl_address [NUM_TQ_ENTRY-1:0] tq_cl_address;
t_word_offset[NUM_TQ_ENTRY-1:0] tq_cl_word_offset; 
logic        [NUM_TQ_ENTRY-1:0] tq_rd_indication; 
t_reg_id     [NUM_TQ_ENTRY-1:0] tq_reg_id; 
t_cl         [NUM_TQ_ENTRY-1:0] next_tq_merge_buffer_data; 
t_cl_address [NUM_TQ_ENTRY-1:0] next_tq_cl_address; 
t_word_offset[NUM_TQ_ENTRY-1:0] next_tq_cl_word_offset; 
logic        [NUM_TQ_ENTRY-1:0] next_tq_rd_indication; 
t_reg_id     [NUM_TQ_ENTRY-1:0] next_tq_reg_id; 

logic sel_reissue;
logic en_reissue_req;

logic set_rd_miss_stall;
logic rst_rd_miss_stall;
logic stall_rd_miss_q;
logic tq_full;

logic rd_hit_pipe_rsp_q3;
logic fill_with_rd_indication_q3;

t_tq_id      rd_miss_tq_id;
t_cl_address rd_miss_cl_address;

logic free_exists;
logic rd_hit_exists;
logic fill_exists;
t_tq_id enc_first_free;
t_tq_id enc_first_fill;
t_tq_id enc_wr_req_hit_mb;
t_tq_id enc_rd_req_hit_mb;

logic set_rd_miss_was_filled;
logic rd_miss_was_filled;
logic [MSB_WORD_OFFSET:LSB_WORD_OFFSET ] new_alloc_word_offset;
logic [4:0] tq_idle_counter;

// Remember the last request that was cancelled due to a miss - will be reissued when the miss is served
assign en_reissue_req   = pipe_early_lu_rsp_q2.rd_miss;
`MAFIA_EN_DFF(reissue_req, pre_core2cache_req, clk, en_reissue_req)


//remember the what request read missed - used to determine if the read miss was served by the fill
`MAFIA_EN_DFF(rd_miss_tq_id,      pipe_early_lu_rsp_q2.lu_tq_id,   clk, en_reissue_req)
`MAFIA_EN_DFF(rd_miss_cl_address, pipe_early_lu_rsp_q2.cl_address, clk, en_reissue_req)


assign set_rd_miss_was_filled = stall_rd_miss_q                                         && 
                                pipe_early_lu_rsp_q2.alloc_rd_fill                      && 
                                (pipe_early_lu_rsp_q2.lu_tq_id   == rd_miss_tq_id)      && 
                                (pipe_early_lu_rsp_q2.cl_address == rd_miss_cl_address) ; 

`MAFIA_EN_RST_DFF(rd_miss_was_filled,  1'b1,   clk, set_rd_miss_was_filled, (rst || sel_reissue) )
assign sel_reissue = rd_miss_was_filled  && (!fill_exists);
assign core2cache_req = sel_reissue  ? reissue_req       : // While stall & alloc_rd_fill , reissue the request. (the rd miss was served by the fill)
                                       pre_core2cache_req; // else, send the request from core

// FIXME - add assertion that a there is no pre_core2cache_req.valid when stall is asserted

assign rd_hit_pipe_rsp_q3     = pipe_lu_rsp_q3.valid               && 
                               (pipe_lu_rsp_q3.lu_op == RD_LU) &&
                               (pipe_lu_rsp_q3.lu_result == HIT);

assign fill_with_rd_indication_q3 = pipe_lu_rsp_q3.valid  && 
                                    (pipe_lu_rsp_q3.lu_op == FILL_LU) &&
                                     pipe_lu_rsp_q3.rd_indication;

assign cache2core_rsp.valid =   rd_hit_pipe_rsp_q3 || fill_with_rd_indication_q3;
//take the relevant word from cache line
assign cache2core_rsp.data    = pipe_lu_rsp_q3.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET] == 2'b00 ?  pipe_lu_rsp_q3.cl_data[31:0]  : 
                                pipe_lu_rsp_q3.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET] == 2'b01 ?  pipe_lu_rsp_q3.cl_data[63:32] : 
                                pipe_lu_rsp_q3.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET] == 2'b10 ?  pipe_lu_rsp_q3.cl_data[95:64] :
                                                                                                    pipe_lu_rsp_q3.cl_data[127:96];
assign cache2core_rsp.address = pipe_lu_rsp_q3.address;
assign cache2core_rsp.reg_id  = pipe_lu_rsp_q3.reg_id; //FIXME



genvar TQ_GEN;
generate for(TQ_GEN=0; TQ_GEN<NUM_TQ_ENTRY; TQ_GEN=TQ_GEN+1) begin : tq_generate_ff_block
    `MAFIA_RST_VAL_DFF(tq_state                  [TQ_GEN], next_tq_state                  [TQ_GEN], clk, rst, S_IDLE)
    `MAFIA_EN_DFF     (tq_rd_indication          [TQ_GEN], next_tq_rd_indication          [TQ_GEN], clk, en_tq_rd_indication          [TQ_GEN]) 
    `MAFIA_EN_DFF     (tq_merge_buffer_data      [TQ_GEN], next_tq_merge_buffer_data      [TQ_GEN], clk, en_tq_merge_buffer_data      [TQ_GEN]) 
    `MAFIA_EN_DFF     (tq_cl_address             [TQ_GEN], next_tq_cl_address             [TQ_GEN], clk, en_tq_cl_address             [TQ_GEN]) 
    `MAFIA_EN_DFF     (tq_cl_word_offset         [TQ_GEN], next_tq_cl_word_offset         [TQ_GEN], clk, en_tq_cl_word_offset         [TQ_GEN]) 
    `MAFIA_EN_DFF     (tq_reg_id                 [TQ_GEN], next_tq_reg_id                 [TQ_GEN], clk, en_tq_reg_id                 [TQ_GEN])
end endgenerate

always_comb begin
    for (int i=0; i<NUM_TQ_ENTRY; ++i) begin
        allocate_entry[i] = first_free[i]               &&  // first free entry to allocate exists
                            core2cache_req.valid        &&  // core request is valid
                            (!any_rd_hit_mb)            &&  // no read hit in merge buffer
                            (!pipe_early_lu_rsp_q2.rd_miss) ;  // no read miss in pipe -> must cancel request, wil be re-issue from the reissue buffer   
    end
    new_alloc_word_offset     = core2cache_req.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET];
    for (int i=0; i<NUM_TQ_ENTRY; ++i) begin
        next_tq_state                  [i] = tq_state[i];
        next_tq_merge_buffer_data[i] = '0;
        next_tq_cl_address       [i] = '0;
        next_tq_rd_indication    [i] = '0;
        next_tq_reg_id           [i] = '0;
        next_tq_cl_word_offset   [i] = '0;

        en_tq_rd_indication      [i] = '0;
        en_tq_cl_word_offset     [i] = '0;
        en_tq_reg_id             [i] = '0;
        en_tq_cl_address         [i] = '0;
        en_tq_merge_buffer_data  [i] = '0;
        unique casez (tq_state[i])
            S_IDLE                : begin
                //if core_req && tq_entry_winner : next_state == LU_CORE_WR/RD_REQ 
                if (allocate_entry[i]) begin
                    next_tq_state[i] =  ((core2cache_req.opcode == RD_OP) ) ?   S_LU_CORE :
                                                                                S_ERROR   ;
                    en_tq_rd_indication             [i] = 1'b1;
                    en_tq_cl_word_offset            [i] = 1'b1;
                    en_tq_reg_id                    [i] = 1'b1;
                    en_tq_cl_address                [i] = 1'b1;
                    en_tq_merge_buffer_data         [i] = 1'b1;
                    next_tq_rd_indication           [i] = (core2cache_req.opcode == RD_OP);
                    next_tq_reg_id                  [i] = core2cache_req.reg_id;
                    next_tq_cl_address              [i] = core2cache_req.address[MSB_TAG:LSB_SET];
                    next_tq_cl_word_offset          [i] = core2cache_req.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET];
                end
            end    
            S_LU_CORE: begin
                //if Cache_hit : nex_state == IDLE
                //if Cache_miss : next_state == MB_WAIT_FILL
                if ((pipe_lu_rsp_q3.tq_id == i) && (pipe_lu_rsp_q3.valid)) begin  
                    next_tq_state[i]=   (pipe_lu_rsp_q3.lu_result == HIT)     ?   S_IDLE            :
                                        (pipe_lu_rsp_q3.lu_result == MISS)    ?   S_MB_WAIT_FILL    :
                                        (pipe_lu_rsp_q3.lu_result == FILL)    ?   S_LU_CORE         : // this FILL is from an older request, don't want it to affect the entry
                                                                                  S_ERROR           ;

                end //((pipe_lu_rsp_q3.tq_id == i) && (pipe_lu_rsp_q3.valid))                    
            end
            S_MB_WAIT_FILL                : begin
                if(fm2cache_rd_rsp.valid && (fm2cache_rd_rsp.address[MSB_TAG:LSB_SET] == tq_cl_address[i])) begin
                    next_tq_state[i] = S_MB_FILL_READY;
                    en_tq_merge_buffer_data  [i] = 1'b1;
                    // If the tq_merge_buffer_e_modified[i][x] is set, then the data in the merge buffer already has the correct data - we don't want to override it with the fill data
                    next_tq_merge_buffer_data[i][31:0]   = fm2cache_rd_rsp.data[31:0];
                    next_tq_merge_buffer_data[i][63:32]  = fm2cache_rd_rsp.data[63:32];
                    next_tq_merge_buffer_data[i][95:64]  = fm2cache_rd_rsp.data[95:64];
                    next_tq_merge_buffer_data[i][127:96] = fm2cache_rd_rsp.data[127:96];
                end

            end //S_MB_WAIT_FILL
            S_MB_FILL_READY               : begin
                if (first_fill[i] && (!core2cache_req.valid)) begin // opportunistic pipe lookup - if no core request, then fill
                    next_tq_state[i] = S_IDLE;
                end //if
            end//S_MB_FILL_READY
            S_ERROR                       : begin
                next_tq_state[i] = tq_state[i];
            end
            default: begin
                next_tq_state[i] = tq_state[i];
            end

        endcase //casez
        //==================================================================================================
        //  Merge buffer hit logic
        //==================================================================================================
                // The case of read after write - we set the read indication and update the offset for the read rsp:
                // an entry that is already set as read indication will merge to the same entry in the merge buffer
                if(rd_req_hit_mb[i]) begin
                    en_tq_rd_indication   [i] = 1'b1;
                    en_tq_cl_word_offset  [i] = 1'b1;
                    en_tq_reg_id          [i] = 1'b1;
                    next_tq_rd_indication [i] = 1'b1;
                    next_tq_cl_word_offset[i] = core2cache_req.address[MSB_WORD_OFFSET:LSB_WORD_OFFSET];
                    next_tq_reg_id        [i] = core2cache_req.reg_id;
                end //if
                
    end //for loop   
end //always_comb

always_comb begin
    for(int i =0; i<NUM_TQ_ENTRY; ++i) begin
        rd_req_hit_mb[i] = core2cache_req.valid             && 
                           (core2cache_req.opcode == RD_OP) &&
                           (core2cache_req.address[MSB_TAG:LSB_SET] == tq_cl_address[i]) &&
                           (!tq_rd_indication[i])           && // if the entry is already set as read indication, then we don't merge to the same entry
                           (!(pipe_early_lu_rsp_q2.rd_miss))&& // the request will be reissued later. we don't want to merge it to the same entry
                           ((tq_state[i] == S_MB_WAIT_FILL) || (tq_state[i] == S_MB_FILL_READY) || (tq_state[i] == S_LU_CORE));    
    end
end

always_comb begin : tq_full_logic
    tq_idle_counter = '0;
    for(int i =0; i<NUM_TQ_ENTRY; ++i) begin
        if(tq_state[i] == S_IDLE) begin     //if there is an idle entry, then no stall
            tq_idle_counter = tq_idle_counter +1;
        end
    end
    tq_full = (tq_idle_counter == 1 ) || (tq_idle_counter == 0 ) ;
end

//sticky stall indication - used for read miss stall logic
assign set_rd_miss_stall = pipe_early_lu_rsp_q2.rd_miss;
assign rst_rd_miss_stall = sel_reissue;
// This is an implementation of a set_rst flop using a en_rst flop
`MAFIA_EN_RST_DFF(stall_rd_miss_q,            // output
                  1'b1 ,  
                  clk, 
                  set_rd_miss_stall,           // set condition
                  (rst_rd_miss_stall || rst) ) // reset condition

//Stall if there is a read miss in pipe q2 or tq full.
assign stall = tq_full || stall_rd_miss_q || set_rd_miss_stall;
assign ready = ~stall;


assign any_rd_hit_mb = |rd_req_hit_mb;

always_comb begin
    for (int i=0; i<NUM_TQ_ENTRY; ++i) begin
        free_entries[i] = (tq_state[i] == S_IDLE);
        fill_entries[i] = (tq_state[i] == S_MB_FILL_READY);
    end
end
`MAFIA_FIND_FIRST(first_free, free_entries)
//suppress the first free entry if there is a read hit in the merge buffer

//FIXME - need to replace with round robin
`MAFIA_FIND_FIRST(first_fill, fill_entries)

`MAFIA_ENCODER(enc_first_free, free_exists, first_free)
`MAFIA_ENCODER(enc_first_fill, fill_exists, first_fill)
`MAFIA_ENCODER(enc_rd_req_hit_mb, rd_hit_exists, rd_req_hit_mb)

//=================
// Pipe lookup mux - core request vs fill request
//=================
always_comb begin
    pipe_lu_req_q1 = '0;
    if(core2cache_req.valid) begin
        if(!pipe_early_lu_rsp_q2.rd_miss) begin // incase of rd miss in q2, then we need to cancel the core request and reissue it later
            pipe_lu_req_q1.valid   = core2cache_req.valid;
            pipe_lu_req_q1.reg_id  = core2cache_req.reg_id;
            pipe_lu_req_q1.lu_op   = (core2cache_req.opcode == RD_OP) ? RD_LU :
                                                                        NO_LU ;
            pipe_lu_req_q1.address       = core2cache_req.address;
            pipe_lu_req_q1.data          = core2cache_req.data;
            pipe_lu_req_q1.tq_id         = any_rd_hit_mb ? enc_rd_req_hit_mb :
                                                            enc_first_free    ;
            pipe_lu_req_q1.mb_hit_cancel = any_rd_hit_mb;
            pipe_lu_req_q1.rd_indication = (core2cache_req.opcode == RD_OP);
        end // pipe_early_lu_rsp_q2.rd_miss
    end else if (fill_exists) begin
        pipe_lu_req_q1.valid         = 1'b1;
        pipe_lu_req_q1.lu_op         = FILL_LU;
        pipe_lu_req_q1.address       = {tq_cl_address      [enc_first_fill],tq_cl_word_offset[enc_first_fill],2'b00} ;//FIXME need to remember the correct address offset for the case that rd indication is set
        pipe_lu_req_q1.cl_data       = tq_merge_buffer_data[enc_first_fill];
        pipe_lu_req_q1.tq_id         = enc_first_fill;
        pipe_lu_req_q1.rd_indication = tq_rd_indication    [enc_first_fill];
        pipe_lu_req_q1.reg_id        = tq_reg_id           [enc_first_fill];
    end //else if

    //incase of a read miss, we need to cancel the request and re-issue it later from the re-issue buffer



end


endmodule
