module capture(clk,rst_n,wrt_smpl,run,capture_done,triggered,trig_pos,
               we,waddr,set_capture_done,armed);

  parameter ENTRIES = 384,		// defaults to 384 for simulation, use 12288 for DE-0
            LOG2 = 9;			// Log base 2 of number of entries
  
  input clk;					// system clock.
  input rst_n;					// active low asynch reset
  input wrt_smpl;				// from clk_rst_smpl.  Lets us know valid sample ready
  input run;					// signal from cmd_cfg that indicates we are in run mode
  input capture_done;			// signal from cmd_cfg register.
  input triggered;				// from trigger unit...we are triggered
  input [LOG2-1:0] trig_pos;	// How many samples after trigger do we capture
  
  output reg we;					// write enable to RAMs
  output reg [LOG2-1:0] waddr;	// write addr to RAMs
  output reg set_capture_done;		// asserted to set bit in cmd_cfg
  output reg armed;				// we have enough samples to accept a trigger

  /// declare state register as type enum ///
  typedef enum reg [1:0] {IDLE, CAPTURE, DONE} state_t;
  state_t state, nxt_state;

  /// declare needed internal registers ///
  reg init;					// state machine output that resets waddr and trig_cnt
  reg inc_addr;				// state machine output that increments the address
  reg inc_trig;				// state machine output that increments trig_cnt
  reg set_armed;				// state machine output that sets armed
  reg clr_armed;				// state machine output that clears armed
  reg [LOG2-1:0] trig_cnt;		// the number of triggers processed
  
  //// declare state transition flop ////
  always_ff @(posedge clk, negedge rst_n)
	if (!rst_n)
		state <= IDLE;
	else
		state <= nxt_state;
		
  // flop for armed
  always_ff @(posedge clk, negedge rst_n)
    if (!rst_n)
	  armed <= 0;
	else if (clr_armed)
	  armed <= 0;
	else if (set_armed)
	  armed <= 1;
		
  // flop for trig_cnt
  always_ff @(posedge clk)
	if (init)
	  trig_cnt <= 0;
	else if (inc_trig)
	  trig_cnt <= trig_cnt + 1;
	  
  // flop for waddr
  always_ff @(posedge clk)
	if (init)
	  waddr <= 0;
	else if (inc_addr)
	  waddr <= (waddr + 1) % ENTRIES;
		
  //// encode state machine ////
  always_comb begin
	// declare default logic
	init = 0;
	inc_addr = 0;
	inc_trig = 0;
	set_armed = 0;
	clr_armed = 0;
	we = 0;
	set_capture_done = 0;
	nxt_state = state;
	case (state)
	  IDLE: begin
		// initialize waddr and trig_cnt to 0 if run and go to CAPTURE state
		if (run) begin
			init = 1;
			nxt_state = CAPTURE;
		end
	  end
	  CAPTURE: begin
	  	// if trig_cnt == trig_pos - 1, and it is still triggered, then we know that trig_cnt should
		// increment again this clk cycle and thus finish the capture
	  	if (trig_cnt == trig_pos) begin
			set_capture_done = 1;
			clr_armed = 1;
			nxt_state = DONE;
		end
		// if wrt_smpl, increment trig_cnt if triggered, and check if the capture is complete
		else if (wrt_smpl) begin
		  we = 1;				// write enable
		  if (triggered) begin
			inc_trig = 1;
		  end
		  // also increment waddr and check whether all addresses are armed
		  inc_addr = 1;	// increment waddr
		  if (waddr + trig_pos == ENTRIES - 1) begin
			set_armed = 1;
		  end
		end
	  end
	  DONE: begin
		// stay in done until capture_done goes low
	    if (!capture_done) begin
		  nxt_state = IDLE;
		end
	  end
	  default:
		nxt_state = IDLE;
	endcase
  end
  
endmodule
