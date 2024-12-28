`default_nettype none
`timescale 1ns/1ps

module SPI_RX_tb();

	/// declare I/O signals for SPI transmitter and receiver
	logic clk, rst_n;	// clk and reset signals
	/// TX I/O
	logic [15:0] tx_data;
	logic wrt, done;
	/// RX I/O
	logic SPItrig, edg, len8;
	logic [15:0] match, mask;
	/// shared signals
	logic SS_n, SCLK, MOSI;
	
	/// declare SPI_TX and SPI_RX DUTs
	SPI_TX DUT_tx(.clk(clk), .rst_n(rst_n), .SS_n(SS_n), .SCLK(SCLK), .wrt(wrt), 
			.done(done), .tx_data(tx_data), .MOSI(MOSI), .pos_edge(~edg), .width8(len8));
	SPI_RX DUT_rx(.clk(clk), .rst_n(rst_n), .SS_n(SS_n), .SCLK(SCLK), .MOSI(MOSI), .edg(edg), 
			.len8(len8), .mask(mask), .match(match), .SPItrig(SPItrig));
	
	initial begin
		/// set initial signals
		clk = 0;
		rst_n = 1;
		wrt = 0;
		
		/// apply reset conditions
		@(negedge clk) rst_n = 0;
		@(negedge clk) rst_n = 1;
		
		/// Test 1: len8 = 0, edg = 0, no mask
		tx_data = 16'hABCD;
		match = 16'hABCD;
		mask = 16'h0000;
		len8 = 0;
		edg = 0;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		
		fork
			begin: test1fail
				@(posedge done);
				$display("Error: Test 1 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig);
				disable test1fail;
			end
		join
		
		/// make sure SPItrig goes back low at the next clk cycle
		@(posedge clk);
		@(negedge clk);
		if (SPItrig) begin
			$display("Error: SPItrig is high for more than one clk cycle.");
			$stop();
		end
		
		/// test 2: same as test 1 but with edg = 1
		edg = 1;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		
		fork
			begin: test2fail
				@(posedge done);
				$display("Error: Test 2 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig)
				disable test2fail;
			end
		join
		
		/// test 3: same as test 1, but without a match
		@(posedge clk);
		@(negedge clk);
		edg = 0;
		match = 16'hABCE;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		fork
			begin
				@(posedge done);
				disable test3fail;
			end
			begin: test3fail
				@(posedge SPItrig)
				$display("Error: Test 3 failed.");
				$stop();
			end
		join
		
		/// test 4: same as test 3, but edit the mask to make the two values match
		@(posedge clk);
		@(negedge clk);
		mask = 16'h0003;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		fork
			begin: test4fail
				@(posedge done);
				$display("Error: Test 4 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig);
				disable test4fail;
			end
		join
		
		/// test 5: same as test 4, but with edg on high
		@(posedge clk);
		@(negedge clk);
		edg = 1;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		fork
			begin: test5fail
				@(posedge done);
				$display("Error: Test 5 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig);
				disable test5fail;
			end
		join
		
		/// test 6: test for when len8 is high and edg is low
		@(posedge clk);
		@(negedge clk);
		len8 = 1;
		edg = 0;
		tx_data = 16'hCDAB;
		match = 16'h00CE;
		mask = 16'h0003;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		fork
			begin: test6fail
				@(posedge done);
				$display("Error: Test 6 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig);
				disable test6fail;
			end
		join
		
		/// test 7: same as test 6 but with edg high
		@(posedge clk);
		@(negedge clk);
		edg = 1;
		@(negedge clk) wrt = 1;	// send the command through
		@(negedge clk) wrt = 0;
		fork
			begin: test7fail
				@(posedge done);
				$display("Error: Test 7 failed.");
				$stop();
			end
			begin
				@(posedge SPItrig);
				disable test7fail;
			end
		join
		
		$display("Yahoo! All tests passed!");
		$stop();
	end

	always
		#5 clk = ~clk;

endmodule

`default_nettype wire