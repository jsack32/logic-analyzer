`default_nettype none

module ComSender(clk, rst_n, cmd, send_cmd, cmd_sent, resp, resp_rdy, TX, RX, clr_resp_rdy);

	input logic clk, rst_n;
	input logic [15:0] cmd;
	input logic send_cmd;	// notifies ComSender to send cmd
	input logic clr_resp_rdy;	// clears resp_rdy
	output logic cmd_sent;	// notifies that the command has been sent
	output logic [7:0] resp;
	output logic resp_rdy;	// notifies that the resp is ready
	output logic TX;
	input logic RX;
	
	/// create state machine inputs and outputs
	logic trmt_sm, tx_done_sm, sel_sm, set_cmd_snt;
	
	/// flop storing lower byte of of cmd
	logic [7:0] lower_byte;
	always_ff @(posedge clk) begin
		if (send_cmd)	// send_cmd acts as an EN for this flop
			lower_byte <= cmd[7:0];
	end
	
	/// infer mux driving tx_data
	wire [7:0] tx_data;
	assign tx_data = sel_sm ? cmd[15:8] : lower_byte;
	
	/// instantiate UART
	UART iUART(.clk(clk), .rst_n(rst_n), .RX(RX), .TX(TX), .rx_rdy(resp_rdy), .clr_rx_rdy(clr_resp_rdy), .rx_data(resp), .trmt(trmt_sm), .tx_data(tx_data), .tx_done(tx_done_sm));
	
	/// create state machine
	typedef enum reg [1:0] {IDLE, HIGH, LOW} state_t;
	state_t state, nxt_state;
	
	/// state transition flop
	always_ff @(posedge clk, negedge rst_n)
		if (!rst_n)
			state <= IDLE;
		else 
			state <= nxt_state;
			
	always_comb begin
		nxt_state = state;
		trmt_sm = 0;
		sel_sm = 0;
		set_cmd_snt = 0;
		case(state)
			/// sending high byte
			HIGH: begin
				if (tx_done_sm) begin
					trmt_sm = 1;
					nxt_state = LOW;
				end
			end
			/// sending low byte
			LOW: begin
				if (tx_done_sm) begin
					set_cmd_snt = 1;
					nxt_state = IDLE;
				end
			end
			/// IDLE state
			IDLE: begin
				if (send_cmd) begin
					sel_sm = 1;
					trmt_sm = 1;
					nxt_state = HIGH;
				end
			end
			default:	// to account for unused state
				nxt_state = IDLE;
		endcase
	end
	
	/// cmd_sent output flop
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n)
			cmd_sent <= 1'b0;
		else if (send_cmd)
			cmd_sent <= 1'b0;	// send_cmd is synch reset
		else if (set_cmd_snt)
			cmd_sent <= 1'b1;	// activate when sm output goes high
	end

endmodule

`default_nettype wire