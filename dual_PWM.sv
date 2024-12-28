`default_nettype none

module dual_PWM(clk, rst_n, VIL, VIH, VIL_PWM, VIH_PWM);

	input logic clk, rst_n;
	input logic [7:0] VIH, VIL;		// duty cycles for high and low PWM signals
	output reg VIH_PWM, VIL_PWM;	// output signals for high and low PWM
	
	/// instantiate high and low PWM with VIH and VIL as duty cycles and VIH_PWM and VIL_PWM as outputs
	pwm8 iVIL_PWM(.clk(clk), .rst_n(rst_n), .duty(VIL), .PWM_sig(VIL_PWM));
	pwm8 iVIH_PWM(.clk(clk), .rst_n(rst_n), .duty(VIH), .PWM_sig(VIH_PWM));

endmodule

`default_nettype wire
