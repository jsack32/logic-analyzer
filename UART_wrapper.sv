`default_nettype none

module UART_wrapper(clk, rst_n, RX, cmd_rdy, clr_cmd_rdy, cmd, send_resp, resp, resp_sent, TX);

	input logic clk, rst_n, RX, clr_cmd_rdy, send_resp;
	input logic [7:0] resp;	// response sent by logic analyzer to software
	output reg cmd_rdy, resp_sent, TX;
	output reg [15:0] cmd;
	
	logic rx_rdy_sm, clr_rdy_sm, capture, set_cmd_rdy;	// rx rdy and clear flags for the state machine
	logic [7:0] rx_data, high_byte;	// the high byte of the cmd
	
	assign cmd = {high_byte, rx_data};
	
	/// instantiate UART
	UART iUART(.clk(clk), .rst_n(rst_n), .RX(RX), .TX(TX), .rx_rdy(rx_rdy_sm), .clr_rx_rdy(clr_rdy_sm), .rx_data(rx_data), .trmt(send_resp), .tx_data(resp), .tx_done(resp_sent));
	
	/// create state machine
	typedef enum reg {IDLE, ACCEPTING} state_t;	/// the byte being transmitted
	state_t state, nxt_state;
	
	/// state transition flop
	always_ff @(posedge clk, negedge rst_n)
		if (!rst_n)
			state <= IDLE;
		else 
			state <= nxt_state;
			
	/// state machine logic
	always_comb begin
		clr_rdy_sm = 0;
		capture = 0;
		set_cmd_rdy = 0;
		nxt_state = state;
		
		case(state)
			IDLE: begin
				if (rx_rdy_sm) begin
					clr_rdy_sm = 1;
					capture = 1;
					nxt_state = ACCEPTING;
				end
			end
			ACCEPTING: begin
				if (rx_rdy_sm) begin
					clr_rdy_sm = 1;
					set_cmd_rdy = 1;
					nxt_state = IDLE;
				end
			end
		endcase
	end
	
	/// high bits register and mux
	always_ff @(posedge clk, negedge rst_n)
		if (!rst_n)
			high_byte <= 8'h00;
		else if (capture)
			high_byte <= rx_data;
	
	/// set_cmd_rdy flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			cmd_rdy <= 1'b0;
		else if(set_cmd_rdy)
			cmd_rdy <= 1'b1;
		else if (clr_cmd_rdy | !RX)
			cmd_rdy <= 1'b0;
	end

endmodule

`default_nettype wire