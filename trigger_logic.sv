`default_nettype none

module trigger_logic(CH1Trig, CH2Trig, CH3Trig, CH4Trig, CH5Trig, protTrig, armed, set_capture_done, clk, rst_n, triggered);

	input logic CH1Trig, CH2Trig, CH3Trig, CH4Trig, CH5Trig, protTrig, armed, set_capture_done, clk, rst_n;
	output reg triggered;
	
	logic trig_d;
	
	/// all triggers must be up, or must be already triggered, for triggered to be high
	/// trig_d is the value to be input into the triggered flop
	assign trig_d = (CH1Trig & CH2Trig & CH3Trig & CH4Trig & CH5Trig & protTrig & armed) | triggered;
	
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			triggered <= 1'b0;
		else if (set_capture_done)	// knock triggered down if capture is done
			triggered <= 1'b0;
		else
			triggered <= trig_d;	// otherwise triggered gets input value to the flop
	end
		
endmodule

`default_nettype wire
