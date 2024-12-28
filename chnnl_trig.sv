module chnnl_trig(clk, rst_n, CH_TrigCfg, armed, CH_Lff5, CH_Hff5, CH_Trig);

	input clk,rst_n;
	input [4:0] CH_TrigCfg;		// 5 channels, inputs come from register in cmd_cfg unit
	input armed;				// Can't allow edge trigger until armed asserted
	input CH_Lff5, CH_Hff5;		// Channel data for low, high, or falling edge triggers
	output logic CH_Trig;		// Channel trigger output 
	
	// Internal signals for edge detection
	logic bit3, bit4;
	logic bit1_output, bit2_output, bit3_output, bit4_output;
	
	// Compute the channel trigger output based on the bit outputs and CH_TrigCfg status
	assign CH_Trig = CH_TrigCfg[0] | (bit1_output && CH_TrigCfg[1]) | (bit2_output && CH_TrigCfg[2]) |
					(bit3_output && CH_TrigCfg[3]) | (bit4_output && CH_TrigCfg[4]);
					
	// FF for bit 4 edge detection, resets when not armed
	always_ff @(posedge CH_Hff5, negedge armed) begin
		if (!armed)
			bit4 <= 0;
		else
			bit4 <= 1;
	end
	
	// FF for bit 3 edge detection, resets when not armed
	always_ff @(negedge CH_Lff5, negedge armed) begin
		if (!armed)
			bit3 <= 0;
		else
			bit3 <= 1;
	end

	// FF for handling low level triggers using CH_Lff5 input
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			bit1_output <= 0;
		else
			bit1_output <= ~CH_Lff5;
	end
	
	// FF for handling high level triggers using CH_Hff5 input 
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			bit2_output <= 0;
		else
			bit2_output <= CH_Hff5;
	end
	
	// FF for outputting status of bit3
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			bit3_output <= 0;
		else
			bit3_output <= bit3;
	end
	
	// FF for outputting status of bit4
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			bit4_output <= 0;
		else
			bit4_output <= bit4;
	end
		
	

endmodule

	