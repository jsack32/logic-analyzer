`default_nettype none

module UART_prot(clk, rst_n, RX, baud_cnt, match, mask, UARTtrig);

	input wire clk, rst_n;	// global inputs
	input wire RX;			// serial data line. comes direct from VIL comparator of CH1
	input wire [15:0] baud_cnt;		// specifies baud rate of UART in number of system clks
	input wire [7:0] match;			// specifies data the UART_rx is looking to match
	input wire [7:0] mask;			// used to mask off bits of match to a don't care for comparison
	output reg UARTtrig;			// asserted for 1 clk cycle at the end of a reception if revieved data matches
	
	reg start, shift, receiving, rx_meta_int, rx_meta, set_rdy;	// signals for the state machine
	reg [15:0] running_baud_cnt;	// the counter that keeps track of how many baud cycles have passed
	reg [3:0] bit_cnt;	// counts the number of bits recieved by the UART_rx
	reg [8:0] rx_shift_reg;	// 9-bit shift register, [7:0] is the data received
	
	assign shift = running_baud_cnt == 0;	// shift after each baud cycle, when running_baud_cnt is 0
	
	// state machine logic
	typedef enum reg {IDLE, RECEIVE} state_t;
	state_t state, nxt_state;
	always_comb begin
		start = 0;
		receiving = 0;
		set_rdy = 0;
		nxt_state = state;
		
		case(state)
			IDLE: begin
				// stay in IDLE until RX becomes 0
				if (!rx_meta) begin
					start = 1;
					nxt_state = RECEIVE;
				end
			end
			RECEIVE: begin
				// receive until 10 bits recieved, then transition back to IDLE and put up ready flag
				receiving = 1;
				if (bit_cnt == 4'd10) begin
					set_rdy = 1;
					nxt_state = IDLE;
				end
			end
		endcase
	end
	
	// state machine flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			state <= IDLE;
		else
			state <= nxt_state;
	end
	
	// counts bit_cnt from 0 to 10 every baud cycle
	always_ff @(posedge clk) begin
		if (start)
			bit_cnt <= 4'h0;
		else if (shift)
			bit_cnt <= bit_cnt + 1;
	end
	
	// counts down from baud count (or half for the first cycle) for every baud cycle
	always_ff @(posedge clk) begin
		if (start)
			running_baud_cnt <= {1'b0, baud_cnt[15:1]};	// start with half the baud rate for receiver
		else if (shift)
			running_baud_cnt <= baud_cnt;
		else if (receiving)
			running_baud_cnt <= running_baud_cnt - 1;
	end
	
	// RX must be double flopped to prevent metastability
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			rx_meta_int <= 1;
			rx_meta <= 1;
		end
		else begin
			rx_meta_int <= RX;
			rx_meta <= rx_meta_int;
		end
	end
	
	// shift bits every baud cycle
	always_ff @(posedge clk) begin
		if (shift)
			rx_shift_reg <= {rx_meta, rx_shift_reg[8:1]};
	end
	
	/// check for match when done receiving
	always_comb begin
		if (!set_rdy)
			UARTtrig = 0;
		else
			UARTtrig = (mask | rx_shift_reg[7:0]) == (mask | match);
	end
	
endmodule

`default_nettype wire