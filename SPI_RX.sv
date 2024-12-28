`default_nettype none

module SPI_RX(clk, rst_n, SS_n, SCLK, MOSI, edg, len8, mask, match, SPItrig);

	input wire clk, rst_n;
	input wire SS_n, SCLK, MOSI;	// SPI protocol signals. coming from VIL comparators
	input wire edg;		// When high the receive shift register should shift on SCLK rise
	input wire len8;	// when high we do an 8-bit comparison to match[7:0], otherwise 16 bit comparison
	input wire [15:0] mask;	// used to mask off bits of match to a don't care for comparison
	input wire [15:0] match;	// data unit is looking to match for a trigger
	output reg SPItrig;	// asserted for 1 clk cycle at end of a reception if received data matches match[7:0]
	
	/// triple flop MOSI and SCLK, twice for metastability and once again to detect rise and fall
	/// double flop SS_n
	logic MOSI_ff1, MOSI_ff2, MOSI_ff3, SCLK_ff1, SCLK_ff2, SCLK_ff3, SS_n_ff1, SS_n_ff2, set_shift;
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			MOSI_ff1 <= 1'b0;
			MOSI_ff2 <= 1'b0;
			MOSI_ff3 <= 1'b0;
			SCLK_ff1 <= 1'b0;
			SCLK_ff2 <= 1'b0;
			SCLK_ff3 <= 1'b0;
			SS_n_ff1 <= 1'b1;	// SS_n must be preset since active low
			SS_n_ff2 <= 1'b1;
		end
		else begin
			MOSI_ff1 <= MOSI;
			MOSI_ff2 <= MOSI_ff1;
			MOSI_ff3 <= MOSI_ff2;
			SCLK_ff1 <= SCLK;
			SCLK_ff2 <= SCLK_ff1;
			SCLK_ff3 <= SCLK_ff2;
			SS_n_ff1 <= SS_n;
			SS_n_ff2 <= SS_n_ff1;
		end
	end
	
	logic SCLK_rise, SCLK_fall;	// create rise and fall signals for SCLK
	assign SCLK_rise = SCLK_ff2 & !SCLK_ff3;	// was low and is now high
	assign SCLK_fall = !SCLK_ff2 & SCLK_ff3;	// was high and is now low
	
	/// state machine to assert shift and done signals
	logic shift, done;
	typedef enum reg {IDLE, RX} state_t;
	state_t state, nxt_state;
	
	/// infer state transition flop
	always_ff @(posedge clk, negedge rst_n)
		if (!rst_n)
			state <= IDLE;
		else
			state <= nxt_state;
			
	/// infer state machine logic
	always_comb begin
		set_shift = 0;
		done = 0;
		nxt_state = state;
		case(state)
			IDLE: begin
				if (!SS_n_ff2)
					nxt_state = RX;
			end
			RX: begin
				if (SS_n_ff2) begin
					done = 1;
					nxt_state = IDLE;
				end
				else
					set_shift = (edg & SCLK_rise) | (!edg & SCLK_fall);	// edg determines whether to look for rise or fall
			end
		endcase
	end

	/// flop for shift
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			shift <= 0;
		else
			shift <= set_shift;
	end
	
	/// infer shift register logic
	logic [15:0] shift_reg;
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			shift_reg <= 0;
		else if (shift)
			shift_reg <= {shift_reg[14:0], MOSI_ff3};
	end
	
	/// check for match
	always_comb
		if (!done)
			SPItrig = 0;
		else if (len8)
			SPItrig = (mask[7:0] | shift_reg[7:0]) == (mask[7:0] | match[7:0]);
		else
			SPItrig = (mask | shift_reg) == (mask | match);

endmodule

`default_nettype wire
