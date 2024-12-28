`default_nettype none
module cmd_cfg(clk,rst_n,resp,send_resp,resp_sent,cmd,cmd_rdy,clr_cmd_rdy,
               set_capture_done,raddr,rdataCH1,rdataCH2,rdataCH3,rdataCH4,
			   rdataCH5,waddr,trig_pos,decimator,maskL,maskH,matchL,matchH,
			   baud_cntL,baud_cntH,TrigCfg,CH1TrigCfg,CH2TrigCfg,CH3TrigCfg,
			   CH4TrigCfg,CH5TrigCfg,VIH,VIL);
			   
  parameter ENTRIES = 384,	// defaults to 384 for simulation, use 12288 for DE-0
            LOG2 = 9;		// Log base 2 of number of entries
			
  input wire clk,rst_n;
  input wire [15:0] cmd;			// 16-bit command from UART (host) to be executed
  input wire cmd_rdy;			// indicates command is valid
  input wire resp_sent;			// indicates transmission of resp[7:0] to host is complete
  input wire set_capture_done;	// from the capture module (sets capture done bit in TrigCfg)
  input wire [LOG2-1:0] waddr;		// on a dump raddr is initialized to waddr
  input wire [7:0] rdataCH1;		// read data from RAMqueues
  input wire [7:0] rdataCH2,rdataCH3;
  input wire [7:0] rdataCH4,rdataCH5;
  output logic [7:0] resp;		// data to send to host as response (formed in SM)
  output logic send_resp;				// used to initiate transmission to host (via UART)
  output logic clr_cmd_rdy;			// when finished processing command use this to knock down cmd_rdy
  output logic [LOG2-1:0] raddr;		// read address to RAMqueues (same address to all queues)
  output logic [LOG2-1:0] trig_pos;	// how many sample after trigger to capture
  output reg [3:0] decimator;	// goes to clk_rst_smpl block
  output reg [7:0] maskL,maskH;				// to trigger logic for protocol triggering
  output reg [7:0] matchL,matchH;			// to trigger logic for protocol triggering
  output reg [7:0] baud_cntL,baud_cntH;		// to trigger logic for UART triggering
  output reg [5:0] TrigCfg;					// some bits to trigger logic, others to capture unit
  output reg [4:0] CH1TrigCfg,CH2TrigCfg;	// to channel trigger logic
  output reg [4:0] CH3TrigCfg,CH4TrigCfg;	// to channel trigger logic
  output reg [4:0] CH5TrigCfg;				// to channel trigger logic
  output reg [7:0] VIH,VIL;					// to dual_PWM to set thresholds
  
  logic [7:0] trig_posH, trig_posL;
  assign trig_pos = {trig_posH, trig_posL};
 
  // State Machine Declaration
  typedef enum reg[2:0] {IDLE, WAIT, DUMP1, DUMP2, DUMP3, WRITE_ST, READ_ST} state_t;
  
  state_t state,nxt_state;
  
    // state machine flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			state <= IDLE;
		else
			state <= nxt_state;
	end

	// Declare and assign opcodes based on cmd.
	logic [5:0] reg_addr;
	logic [7:0] data;
	logic [2:0] channel;
	logic read, write, dump;
	assign read = (cmd[15:14] == 2'b00);
	assign write = (cmd[15:14] == 2'b01);
	assign dump = (cmd[15:14] == 2'b10);		// don't really need, but easier to read
												// however, this is an extra wire
	// Declare and assign other signals from cmd.
	assign reg_addr = cmd[13:8];
	assign data = cmd[7:0];
	assign channel = cmd[10:8];
	
	// Register write enable signals
	logic write_01, write_02, write_03, write_04, write_05, write_06, write_07, write_08, write_09,
			write_10, write_11, write_12, write_13, write_14, write_15, write_16, write_17;
			
	// Initialization and increment signals
	logic init, inc;
  
	// state machine logic
	always_comb begin
		send_resp = 0;
		resp = 8'hEE;
		init = 0;
		inc = 0;
		clr_cmd_rdy = 0;
		nxt_state = state;
		write_01 = 0;
		write_02 = 0;
		write_03 = 0;
		write_04 = 0;
		write_05 = 0;
		write_06 = 0;
		write_07 = 0;
		write_08 = 0;
		write_09 = 0;
		write_10 = 0;
		write_11 = 0;
		write_12 = 0;
		write_13 = 0;
		write_14 = 0;
		write_15 = 0;
		write_16 = 0;
		write_17 = 0;
		
		case (state)
			IDLE: begin
				// Wait for command to be ready
				if(cmd_rdy) begin
					// Check command signals 
					if(dump) begin
						init = 1;				// initialize dump
						nxt_state = DUMP1;		// move to first dump state
					end
					else if(write) begin
						nxt_state = WRITE_ST;	// move to write state
					end
					else if(read) begin
						nxt_state = READ_ST;	// move to read state
					end
					else begin
						send_resp = 1;
						nxt_state = WAIT;
					end
				end 
			end
			
			WAIT: begin
				if(resp_sent) begin
					clr_cmd_rdy = 1;
					nxt_state = IDLE;
				end
			end
			
			DUMP1: begin
				nxt_state = DUMP2;	
			end
			
			DUMP2: begin	
				inc = 1;					// intermediate state for dump (wait state)
				send_resp = 1;				// trigger the response send
				nxt_state = DUMP3;
				
				// Set response based on channel input 
				if(channel == 1)
					resp = rdataCH1;
				else if(channel == 2)
					resp = rdataCH2;
				else if(channel == 3)
					resp = rdataCH3;
				else if(channel == 4)
					resp = rdataCH4;
				else if(channel == 5)
					resp = rdataCH5;
				else begin
					nxt_state = WAIT;
				end
			end
			
			DUMP3: begin
				if (raddr == waddr) begin
					clr_cmd_rdy = 1;		// clear command ready to end case
					nxt_state = IDLE;		// once finished, return to idle state
				end
				else if (resp_sent) begin
					nxt_state = DUMP2;
				end
			end
				
			WRITE_ST: begin
				// Write data to respective register based on register address
				resp = 8'hA5;
				if(reg_addr == 0)
					write_01 = 1;
				else if(reg_addr == 1)
					write_02 = 1;
				else if(reg_addr == 2)
					write_03 = 1;
				else if(reg_addr == 3)
					write_04 = 1;
				else if(reg_addr == 4)
					write_05 = 1;
				else if(reg_addr == 5)
					write_06 = 1;
				else if(reg_addr == 6)
					write_07 = 1;
				else if(reg_addr == 7)
					write_08 = 1;
				else if(reg_addr == 8)
					write_09 = 1;
				else if(reg_addr == 9)
					write_10 = 1;
				else if(reg_addr == 10)
					write_11 = 1;
				else if(reg_addr == 11)
					write_12 = 1;
				else if(reg_addr == 12)
					write_13 = 1;
				else if(reg_addr == 13)
					write_14 = 1;
				else if(reg_addr == 14)
					write_15 = 1;
				else if(reg_addr == 15)
					write_16 = 1;
				else if(reg_addr == 16)
					write_17 = 1;
				send_resp = 1;
				// need to ack resp_sent and go back to IDLE
				nxt_state = WAIT;
			end
			READ_ST: begin
				// Read data from the respective register based on register address
				if(reg_addr == 0)
					resp = TrigCfg;
				else if(reg_addr == 1)
					resp = CH1TrigCfg;
				else if(reg_addr == 2)
					resp = CH2TrigCfg;
				else if(reg_addr == 3)
					resp = CH3TrigCfg;
				else if(reg_addr == 4)
					resp = CH4TrigCfg;
				else if(reg_addr == 5)
					resp = CH5TrigCfg;
				else if(reg_addr == 6)
					resp = decimator;
				else if(reg_addr == 7)
					resp = VIH;
				else if(reg_addr == 8)
					resp = VIL;
				else if(reg_addr == 9)
					resp = matchH;
				else if(reg_addr == 10)
					resp = matchL;
				else if(reg_addr == 11)
					resp = maskH;
				else if(reg_addr == 12)
					resp = maskL;
				else if(reg_addr == 13)
					resp = baud_cntH;
				else if(reg_addr == 14)
					resp = baud_cntL;
				else if(reg_addr == 15)
					resp = trig_posH;
				else if(reg_addr == 16)
					resp = trig_posL;
				send_resp = 1;
				// need to ack resp_sent and go back to IDLE
				nxt_state = WAIT;
			end
			default:
				nxt_state = IDLE;
		endcase
	end
	
	// raddr flip flop logic
	always_ff @(posedge clk) begin
		if(init)
			raddr <= waddr;
		else if (inc)
			raddr <= (raddr + 1) % ENTRIES;	// increment
	end
	
	
	// Declare 17 flops (register set)
	// Register 1
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			TrigCfg <= 6'h03;
		else if(write_01) 
			TrigCfg <= data;
		else if (set_capture_done)
			TrigCfg[5] <= 1;
	end
	
	// Register 2
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			CH1TrigCfg <= 5'h01;
		else if(write_02) 
			CH1TrigCfg <= data;
	end
	
	// Register 3
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			CH2TrigCfg <= 5'h01;
		else if(write_03) 
			CH2TrigCfg <= data;
	end
	
	// Register 4
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			CH3TrigCfg <= 5'h01;
		else if(write_04) 
			CH3TrigCfg <= data;
	end
	
	// Register 5
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			CH4TrigCfg <= 5'h01;
		else if(write_05) 
			CH4TrigCfg <= data;
	end
	
	// Register 6
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			CH5TrigCfg <= 5'h01;
		else if(write_06) 
			CH5TrigCfg <= data;
	end
	
	// Register 7
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			decimator <= 4'h0;
		else if(write_07) 
			decimator <= data;
	end
	
	// Register 8
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			VIH <= 8'hAA;
		else if(write_08) 
			VIH <= data;
	end
	
	// Register 9
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			VIL <= 8'h55;
		else if(write_09) 
			VIL <= data;
	end
	
	// Register 10
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			matchH <= 8'h00;
		else if(write_10) 
			matchH <= data;
	end
	
	// Register 11
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			matchL <= 8'h00;
		else if(write_11) 
			matchL <= data;
	end
	
	// Register 12
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			maskH <= 8'h00;
		else if(write_12) 
			maskH <= data;
	end
	
	// Register 13
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			maskL <= 8'h00;
		else if(write_13) 
			maskL <= data;
	end
	
	// Register 14
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			baud_cntH <= 8'h06;
		else if(write_14) 
			baud_cntH <= data;
	end
	
	// Register 15
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			baud_cntL <= 8'hC8;
		else if(write_15) 
			baud_cntL <= data;
	end
	
	// Register 16
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			trig_posH <= 8'h00;
		else if(write_16) 
			trig_posH <= data;
	end
	
	// Register 17
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			trig_posL <= 8'h01;
		else if(write_17) 
			trig_posL <= data;
	end

endmodule
`default_nettype wire
  