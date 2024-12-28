`default_nettype none

module pwm8(clk, rst_n, duty, PWM_sig);

	input logic clk, rst_n;
	input logic [7:0] duty;
	output reg PWM_sig;
	
	logic [7:0] cnt;
	
	/// flop to count up every clk cycle
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			cnt <= 8'h00;
		else
			cnt <= cnt + 1;
	end
	
	/// flop ensures that signal is high while cnt is less than duty
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			PWM_sig <= 1'b0;
		else if (cnt <= duty)	// signal is high when cnt is less than duty
			PWM_sig <= 1'b1;
		else 					// signal low for the rest of the count
			PWM_sig <= 1'b0;
	end

endmodule

`default_nettype wire
