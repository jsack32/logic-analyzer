module RAMqueue(clk, we, waddr, wdata, raddr, rdata);

	parameter ENTRIES = 384;
	parameter LOG2 = $clog2(ENTRIES);

	input clk, we;
	input [LOG2-1:0] waddr, raddr;
	input [7:0] wdata;
	output reg [7:0] rdata;
	
	// synopsys translate_off
	reg [7:0] mem[0:ENTRIES-1];	// the memory being read and written to
	
	always_ff@(posedge clk) begin
		rdata <= mem[raddr];	// read data from memory
		if (we) begin
			mem[waddr] <= wdata;	// write into memory if en is high
		end
	end
	// synopsys translate_on

endmodule
