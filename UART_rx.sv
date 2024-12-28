`default_nettype none

module UART_rx(clk, rst_n, RX, clr_rdy, rx_data, rdy);

	input logic clk, rst_n, RX, clr_rdy;
	output logic [7:0] rx_data;
	output logic rdy;
	
	logic [3:0] bit_cnt;	// counts the number of bits recieved by the UART_rx
	logic [5:0] baud_cnt;	// counts down from 34 clk cycles each baud cycle
	logic start, shift, receiving, rx_meta_int, rx_meta, set_rdy;	// intermediate signals
	logic [8:0] rx_shift_reg;	// 9-bit shift register
	
	assign shift = baud_cnt == 0;	// shift after each baud cycle, when baud_cnt is 0
	assign rx_data = rx_shift_reg[7:0];
	
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
	
	// counts down from 34 (or 17 for the first cycle) for every baud cycle
	always_ff @(posedge clk) begin
		if (start)
			baud_cnt <= 6'd17;
		else if (shift)
			baud_cnt <= 6'd34;
		else if (receiving)
			baud_cnt <= baud_cnt - 1;
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
	
	// ready flip flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			rdy <= 0;
		else if (start | clr_rdy)
			rdy <= 0;
		else if (set_rdy)
			rdy <= 1;
	end

endmodule

`default_nettype wire