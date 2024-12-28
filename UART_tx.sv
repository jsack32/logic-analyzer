`default_nettype none

module UART_tx(clk, rst_n, TX, trmt, tx_data, tx_done);
	
	input logic clk, rst_n, trmt;
	input logic [7:0] tx_data;
	output reg TX, tx_done;
	
	logic init, shift, transmitting, set_done;
	logic [3:0] bit_cnt;	// output for the leftmost flop, counts up to 10 bits
	logic [5:0] baud_cnt;	// output for middle flip flop (bit audible)
	logic [8:0] tx_shift_reg;	// output for rightmost flop
	
	assign TX = tx_shift_reg[0];
	
	typedef enum reg {IDLE, TRANSMIT} state_t;
	state_t state, nxt_state;		// the states for the state machine
	
	always_comb begin
		init = 0;
		transmitting = 0;
		set_done = 0;
		nxt_state = state;
		
		case (state)
			// stay in IDLE unless trmt is high
			IDLE: begin
				if (trmt) begin
					init = 1;	// initialize the state machine
					nxt_state = TRANSMIT;	// transition to TRANSMIT state
				end
			end
			// keep transmitting until 10 bits have been transmitted
			TRANSMIT: begin
				transmitting = 1;
				if (bit_cnt == 4'd10) begin	// if 10 bits transmitted
					set_done = 1;		// let user know that transmitting is complete
					nxt_state = IDLE;	// go back to IDLE
				end
			end
		endcase
	end
	
	// state machine flop for UART transmitter state transitions
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			state <= IDLE;
		else
			state <= nxt_state;
	end
	
	// counts the number of bits shifted every 34 clk cycles (up to 10)
	always_ff @(posedge clk) begin
		if (init)
			bit_cnt <= 4'h0;
		else if (shift)
			bit_cnt <= bit_cnt + 1;
	end
	
	// counts up to 34 clk cycles and asserts shift when 34 cycles pass
	always_ff @(posedge clk) begin
		if (init | shift)
			baud_cnt <= 6'h00;
		else if (transmitting)
			baud_cnt <= baud_cnt + 1;
	end
	
	assign shift = baud_cnt == 6'd34;

	// this flop shifts the bits every 34 clk cycles
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			tx_shift_reg <= 9'b111111111;
		else if (init)
			tx_shift_reg <= {tx_data, 1'b0};
		else if (shift)
			tx_shift_reg <= {1'b1, tx_shift_reg[8:1]};
	end
	
	// bottom flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			tx_done <= 1'b0;
		else if (init)		// if beginning to transmit a new vector, knock tx_done down
			tx_done <= 1'b0;
		else if (set_done)
			tx_done <= 1'b1;	// set tx_done to high if transmission signal is complete
	end

endmodule

`default_nettype wire