`default_nettype none

module channel_sample(clk, rst_n, smpl_clk, CH_H, CH_L, CH_Hff5, CH_Lff5, smpl);

input logic clk, rst_n;
input logic smpl_clk;	// decimated clk from clk_rst_smpl, samples are captured on negedge of this clk
input logic CH_H, CH_L;	// unsynchronized channel samples from the comparators comparing against VIH, VIL
output logic CH_Hff5, CH_Lff5;	// 5th flopped versions of channels going on to the trigger logic
output logic [7:0] smpl;		// 8-bit sample that will get written to the RAMqueue for that channel
								// it is a collection of 4 2-bit samples
								
logic CH_Hff1, CH_Hff2, CH_Hff3, CH_Hff4;	// intermediate flopped signals of CH_H
logic CH_Lff1, CH_Lff2, CH_Lff3, CH_Lff4;	// intermediate flopped signals of CH_L

/// flop CH_H and CH_L twice for metastability, and 3 more times to generate the sample
/// this block represents 10 total flip flops that are clocked by smpl_clk
always_ff @(negedge smpl_clk) begin
	/// flop high signal 5 times
	CH_Hff1 <= CH_H;
	CH_Hff2 <= CH_Hff1;
	CH_Hff3 <= CH_Hff2;
	CH_Hff4 <= CH_Hff3;
	CH_Hff5 <= CH_Hff4;
	
	/// flop low signal 5 times
	CH_Lff1 <= CH_L;
	CH_Lff2 <= CH_Lff1;
	CH_Lff3 <= CH_Lff2;
	CH_Lff4 <= CH_Lff3;
	CH_Lff5 <= CH_Lff4;
end

/// create flop for updating smpl that updates at the system clk
always_ff @(posedge clk) begin
	smpl <= {CH_Hff2, CH_Lff2, CH_Hff3, CH_Lff3, CH_Hff4, CH_Lff4, CH_Hff5, CH_Lff5};
end

endmodule

`default_nettype wire