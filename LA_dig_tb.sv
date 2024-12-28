`timescale 1ns / 1ps
`default_nettype none

module LA_dig_tb();
			
//// Interconnects to DUT/support defined as type wire /////
wire clk400MHz,locked;			// PLL output signals to DUT
wire clk;						// 100MHz clock generated at this level from clk400MHz
wire VIH_PWM,VIL_PWM;			// connect to PWM outputs to monitor
wire CH1L,CH1H,CH2L,CH2H,CH3L;	// channel data inputs from AFE model
wire CH3H,CH4L,CH4H,CH5L,CH5H;	// channel data inputs from AFE model
wire RX,TX;						// interface to host
wire cmd_sent,resp_rdy;			// from master UART, monitored in test bench
wire [7:0] resp;				// from master UART, reponse received from DUT
wire tx_prot;					// UART signal for protocol triggering
wire SS_n,SCLK,MOSI;			// SPI signals for SPI protocol triggering
wire CH1L_mux,CH1H_mux;         // output of muxing logic for CH1 to enable testing of protocol triggering
wire CH2L_mux,CH2H_mux;			// output of muxing logic for CH2 to enable testing of protocol triggering
wire CH3L_mux,CH3H_mux;			// output of muxing logic for CH3 to enable testing of protocol triggering

////// Stimulus is declared as type reg ///////
reg REF_CLK, RST_n;
reg [15:0] host_cmd;			// command host is sending to DUT
reg send_cmd;					// asserted to initiate sending of command
reg clr_resp_rdy;				// asserted to knock down resp_rdy
reg [1:0] clk_div;				// counter used to derive 100MHz clk from clk400MHz
reg strt_tx;					// kick off unit used for protocol triggering
reg en_AFE;
reg capture_done_bit;			// flag used in polling for capture_done
reg [7:0] res,exp;				// used to store result and expected read from files

/// hold values for operation, upper byte, and lower byte for cmd cnf ///
reg [1:0] op;					// specifies the operation for a command
reg [5:0] addr_or_chnl;			// specifies the read/write addr, or the channel for a dmp cmd
reg [7:0] data_byte;
			// the byte of data used for a write command
assign host_cmd = {op, addr_or_chnl, data_byte};	// parse above signals to full 2-byte cmd

/// hold logic for easy testing for posAck and negAck ///
reg posAck;
reg negAck;
assign posAck = resp_rdy & (resp == 8'ha5);
assign negAck = resp_rdy & (resp == 8'hee);

wire AFE_clk;

///////////////////////////////////////////
// Channel Dumps can be written to file //
/////////////////////////////////////////
integer fptr1;		// file pointer for T1 dumps
integer fptr2;		// file pointer for T2 dumps
integer fptr3;		// file pointer for T3 dumps
integer fptr4;		// file pointer for T4 dumps
integer fptr5;		// file pointer for T5 dumps
// more file handles for dumps of other channels??? //
integer fexp;		// file pointer to file with expected results
integer found_res,found_expected,loop_cnt;
integer mismatches;	// number of mismatches when comparing results to expected
integer sample;		// sample counter in dump & compare

/////////////////////////////////
reg UART_triggering;	// set to true if testing UART based triggering
reg SPI_triggering;		// set to true if testing SPI based triggering

assign AFE_clk = en_AFE & clk400MHz;
///// Instantiate Analog Front End model, provides stimulus to channels ///////
AFE iAFE(.smpl_clk(AFE_clk),.VIH_PWM(VIH_PWM),.VIL_PWM(VIL_PWM),
         .CH1L(CH1L),.CH1H(CH1H),.CH2L(CH2L),.CH2H(CH2H),.CH3L(CH3L),
         .CH3H(CH3H),.CH4L(CH4L),.CH4H(CH4H),.CH5L(CH5L),.CH5H(CH5H));
		 
//// Mux for muxing in protocol triggering for CH1 /////
assign {CH1H_mux,CH1L_mux} = (UART_triggering) ? {2{tx_prot}} :		// assign to output of UART_tx used to test UART triggering
                             (SPI_triggering) ? {2{SS_n}}: 			// assign to output of SPI SS_n if SPI triggering
				             {CH1H,CH1L};

//// Mux for muxing in protocol triggering for CH2 /////
assign {CH2H_mux,CH2L_mux} = (SPI_triggering) ? {2{SCLK}}: 			// assign to output of SPI SCLK if SPI triggering
				             {CH2H,CH2L};	

//// Mux for muxing in protocol triggering for CH3 /////
assign {CH3H_mux,CH3L_mux} = (SPI_triggering) ? {2{MOSI}}: 			// assign to output of SPI MOSI if SPI triggering
				             {CH3H,CH3L};					  
	 
////// Instantiate DUT ////////		  
LA_dig iDUT(.clk400MHz(clk400MHz),.RST_n(RST_n),.locked(locked),
            .VIH_PWM(VIH_PWM),.VIL_PWM(VIL_PWM),.CH1L(CH1L_mux),.CH1H(CH1H_mux),
			.CH2L(CH2L_mux),.CH2H(CH2H_mux),.CH3L(CH3L_mux),.CH3H(CH3H_mux),.CH4L(CH4L),
			.CH4H(CH4H),.CH5L(CH5L),.CH5H(CH5H),.RX(RX),.TX(TX));

///// Instantiate PLL to provide 400MHz clk from 50MHz ///////
pll8x iPLL(.ref_clk(REF_CLK),.RST_n(RST_n),.out_clk(clk400MHz),.locked(locked));

///// It is useful to have a 100MHz clock at this level similar //////
///// to main system clock (clk).  So we will create one        //////
always @(posedge clk400MHz, negedge locked)
  if (~locked)
    clk_div <= 2'b00;
  else
    clk_div <= clk_div+1;
assign clk = clk_div[1];

//// Instantiate Master UART (mimics host commands) //////
ComSender iSNDR(.clk(clk), .rst_n(RST_n), .RX(TX), .TX(RX),
                .cmd(host_cmd), .send_cmd(send_cmd),
		.cmd_sent(cmd_sent), .resp_rdy(resp_rdy),
		.resp(resp), .clr_resp_rdy(clr_resp_rdy));
					 
////////////////////////////////////////////////////////////////
// Instantiate transmitter as source for protocol triggering //
//////////////////////////////////////////////////////////////
reg  [7:0]  UART_tx_data; // values is configured in UART tests
reg  [7:0]  baudH;
reg  [7:0]  baudL;
reg [15:0]  baud;
assign baud = {baudH, baudL};

wire done;	// done signal for UART/SPI transmission
UART_tx_cfg_bd iTX(.clk(clk), .rst_n(RST_n), .TX(tx_prot), .trmt(strt_tx),
            .tx_data(UART_tx_data), .tx_done(done), .baud(baud));
					 
////////////////////////////////////////////////////////////////////
// Instantiate SPI transmitter as source for protocol triggering //
//////////////////////////////////////////////////////////////////
reg [15:0] SPI_tx_data;
reg [7:0] matchH, matchL;
reg pos_edge;
reg width8;

SPI_TX iSPI(.clk(clk),.rst_n(RST_n),.SS_n(SS_n),.SCLK(SCLK), .wrt(strt_tx), .done(done),
            .tx_data(SPI_tx_data), .MOSI(MOSI), .pos_edge(pos_edge), .width8(width8));
			 
reg err;	// flag that goes up if there is an error

reg t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11;
//Test selector (Y/N) = (1/0)
assign t1  = 1;  //// TEST 1: test CH1 triggering from AFE ////
assign t2  = 1;  //// TEST 2: test CH2 triggering from AFE with different pos ////
assign t3  = 1;  //// TEST 3: test CH2 with AFE negative triggering ////
assign t4  = 1;  //// TEST 4: test CH3 with AFE negative triggering with different decimator////
assign t5  = 1;  //// TEST 5: test CH1 negative edge triggering from AFE with different voltages////
assign t6  = 1;  //// TEST 6: test  UART triggering match different baud ////
assign t7  = 1;  //// TEST 7: test UART triggering no match default baud ////
assign t8  = 1;  //// TEST 8: test SPI match with default mask, posedge trigger, 16 bits////
assign t9  = 1;  //// TEST 9: test SPI triggering different mask negative edge, only 8 bits ////
assign t10 = 1;  //// TEST 10: test SPI triggering with no match triggered on posedge //// 
assign t11 = 1;  


initial begin
	err = 0;

	if (t1) begin
		//////////////////////////////////////////////
		//// TEST 1: test CH1 triggering from AFE ////
		//////////////////////////////////////////////
		initialize;	            // initializes all stimulus to DUT and performs a global reset
		fptr1 = $fopen("CH1dmp.txt","w"); // open file to write CH1 dumps to
		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;            // do not initiate protocol trigger for now

		////// Set for CH1 triggering on positive edge //////
		op = 2'b01;				// turn on write mode
		addr_or_chnl = 6'h01;	// write to CH1TrigCfg (0x01)
		data_byte = 8'h10;		// trigger on the positive edge
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;
		////// Leave all other registers at their default /////
		////// and set RUN bit, but enable AFE first //////
    	en_AFE = 1;
		addr_or_chnl = 6'h00;   // write to TrigCfg (0x00)
		data_byte = 8'h13;		// set run bit, keep prot triggering off
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done;
    	//// Now request CH1 dump ////
		op = 2'b10;				// turn on dump mode
		addr_or_chnl = 6'h01;	// dump channel 1
		snd_cmd;				// send the command, waits for cmd_sent
		//// Now collect CH1 dump into a file ////
    	collect_dump(.fptr(fptr1));
		//// Now compare CH1dmp.txt to expected results ////
		fexp = $fopen("test1_expected.txt","r");
		fptr1 = $fopen("CH1dmp.txt","r");
		$display("Starting comparison for CH1");
		compare(.fptr(fptr1), .fexp(fexp), .n(1));
	end

    if (t2) begin
		/////////////////////////////////////////////////////////////////
		//// TEST 2: test CH2 triggering from AFE with different pos ////
		/////////////////////////////////////////////////////////////////
		initialize;	                      // initializes all stimulus to DUT and performs a global reset
		fptr2 = $fopen("CH2dmp.txt","w"); // open file to write CH1 dumps to
		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;            // do not initiate protocol trigger for now

		////// Set for CH1 triggering on positive edge //////
		op = 2'b01;				// turn on write mode
		addr_or_chnl = 6'h02;	// write to CH2TrigCfg (0x02)
		data_byte = 8'h10;		// trigger on the positive edge
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;
		////// Changing posH and posL /////
		addr_or_chnl = 6'h0F;	// write to posH (0x0F)
		data_byte = 8'hAB;		// set it to AB
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h10;	// write to posL (0x10)
		data_byte = 8'h00;		// set it to 0
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;

		////// and set RUN bit, but enable AFE first //////
   		en_AFE = 1;
		addr_or_chnl = 6'h00;   // write to TrigCfg (0x00)
		data_byte = 8'h13;		// set run bit, keep prot triggering off
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done;
    	//// Now request CH2 dump ////
		op = 2'b10;				// turn on dump mode
		addr_or_chnl = 6'h02;	// dump channel 1
		snd_cmd;				// send the command, waits for cmd_sent
		//// Now collect CH1 dump into a file ////
    	collect_dump(.fptr(fptr2));
		//// Now compare CH1dmp.txt to expected results ////
		fexp = $fopen("test2_expected.txt","r");
		fptr2 = $fopen("CH2dmp.txt","r");
		$display("Starting comparison for T2_CH2");
		compare(.fptr(fptr2), .fexp(fexp), .n(2));
	end

	if (t3) begin
		///////////////////////////////////////////////////////
		//// TEST 3: test CH2 with AFE negative triggering ////
		///////////////////////////////////////////////////////
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		fptr2 = $fopen("CH2dmp.txt", "w");
		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;			 // do not initiate protocol trigger for now
		////// Set for CH2 for triggering on negative edge //////
		op = 2'b01;				 // turn on write mode
		addr_or_chnl = 6'h02;	 // write to CH2TrigCfg (0x02)
		data_byte = 8'b01000; // trigger on the negative edge
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;
		////// Leave all other registers at their default /////
		////// and set RUN bit, but enable AFE first //////
    	en_AFE = 1;
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte = 8'h13;        // set run bit, keep prot triggering off
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done;
   		//// Now request CH2 dump ////
		op = 2'b10;				  // turn on dump mode
		addr_or_chnl = 6'h02;	  // dump channel 2
		snd_cmd;				  // send the command, waits for cmd_sent
		//// Now collect CH2 dump into a file ////
    	collect_dump(.fptr(fptr2));
		//// Now compare CH1dmp.txt to expected results ////
		fexp = $fopen("test3_expected.txt","r");
		fptr2 = $fopen("CH2dmp.txt","r");
		$display("Dump complete for CH2");
		compare(.fptr(fptr2), .fexp(fexp), .n(3));
	end

	if (t4) begin
		///////////////////////////////////////////////////////////////////////////////
		//// TEST 4: test CH3 with AFE negative triggering with different decimator////
		///////////////////////////////////////////////////////////////////////////////
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		fptr3 = $fopen("CH3dmp.txt", "w");
		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;			 // do not initiate protocol trigger for now
		////// Set for CH2 for triggering on negative edge //////
		op = 2'b01;				 // turn on write mode
		addr_or_chnl = 6'h03;	 // write to CH3TrigCfg (0x03)
		data_byte = 8'b01000;    // trigger on the negative edge
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;
		////// changing decimator /////
		addr_or_chnl = 6'h06;	 // write to decimator (0x06)
		data_byte = 8'h03;        // set the decimator to 8 (2^3)
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		////// and set RUN bit, but enable AFE first //////
    	en_AFE = 1;
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte = 8'h13;        // set run bit, keep prot triggering off
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done;
    	//// Now request CH2 dump ////
		op = 2'b10;				  // turn on dump mode
		addr_or_chnl = 6'h03;	  // dump channel 3
		snd_cmd;				  // send the command, waits for cmd_sent
		//// Now collect CH2 dump into a file ////
    	collect_dump(.fptr(fptr3));
		//// Now compare CH3dmp.txt to expected results ////
		fexp = $fopen("test4_expected.txt","r");
		fptr3 = $fopen("CH3dmp.txt","r");
		$display("Dump complete for  T4_CH3");
		compare(.fptr(fptr3), .fexp(fexp), .n(4));
	end

	if (t5) begin 
		////////////////////////////////////////////////////////////////////////////////////
		//// TEST 5: test CH1 negative edge triggering from AFE with different voltages ////
		////////////////////////////////////////////////////////////////////////////////////
		initialize;	            // initializes all stimulus to DUT and performs a global reset
		fptr1 = $fopen("CH1dmp.txt","w"); // open file to write CH1 dumps to
		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;            // do not initiate protocol trigger for now

		////// Set for CH1 triggering on negative edge //////
		op = 2'b01;				// turn on write mode
		addr_or_chnl = 6'h01;	// write to CH1TrigCfg (0x01)
		data_byte = 8'h08;		// trigger on the negative edge
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;

		////// set the volatges to be different /////
		addr_or_chnl = 6'h07;	// write to VIH (0x07)
		data_byte = 8'hFE;		// set VIH to max 3.3V
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h08;	// write to VIL (0x08)
		data_byte = 8'h0F;		// set VIL to 15 
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;

		////// and set RUN bit, but enable AFE first //////
    	en_AFE = 1;
		addr_or_chnl = 6'h00;   // write to TrigCfg (0x00)
		data_byte = 8'h13;		// set run bit, keep prot triggering off
    	snd_cmd;				// send the command, waits for cmd_sent
		check_posAck;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done;
    	//// Now request CH1 dump ////
		op = 2'b10;				// turn on dump mode
		addr_or_chnl = 6'h01;	// dump channel 1
		snd_cmd;				// send the command, waits for cmd_sent
		//// Now collect CH1 dump into a file ////
    	collect_dump(.fptr(fptr1));
		//// Now compare CH1dmp.txt to expected results ////
		fexp = $fopen("test5_expected.txt","r");
		fptr1 = $fopen("CH1dmp.txt","r");
		$display("Starting comparison for CH1");
		compare(.fptr(fptr1), .fexp(fexp), .n(5));
	end

	if (t6) begin
		////////////////////////////////////////////////////////////////////
		//// TEST 6: test  UART triggering match different baud ////////////
		///////////////////////////////////////////////////////////////////
		// default baud values
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		UART_triggering = 1;     
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;
		////// Set for UART for triggering //////
		op = 2'b01;				 // turn on write mode

		// we are going to use default baud values
		baudH = 8'h06;
		baudL = 8'hFF;

		UART_tx_data = 8'b01110101;    	// set tx_data value to 34

		addr_or_chnl = 6'h0A;	 		// write to matchL (0x0A)
		data_byte = 8'b11111011;   		// match is set to UART_tx_data
   		snd_cmd;				 		// send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h0C;    		// write to maskL (0x0C)
		data_byte = 8'b10001110;       	// set mask bits to 00001111
		snd_cmd;
		check_posAck;
		////// Leave all other registers at their default /////
		////// and set RUN bit //////
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte = 8'h12;        // set run bit, keep UART triggering on
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		snd_tx;					 // tells the UART to start transmit
		//// If capture done bit is set, match is detected ////
		poll_for_capture_done_match(6);
	end

	if (t7) begin	
		///////////////////////////////////////////////////////////////
		//// TEST 7: test UART triggering no match default baud ///////
		///////////////////////////////////////////////////////////////
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		UART_triggering = 1;     // using UART triggering
		SPI_triggering = 0;      // SPI is disabled
		en_AFE = 0;        
		strt_tx = 0;
		////// Set for UART for triggering //////
		op = 2'b01;				 // turn on write mode

		/// writing the baudL value to default

		baudL = 8'hC8;
		addr_or_chnl = 6'h0E;	 // write to baudL (0x0E)
		data_byte = baudL;       // set baudL values
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		/// Writing the match value 

		UART_tx_data = 8'd30;
		addr_or_chnl = 6'h0A;	  // write to matchL (0x0A)
		data_byte = 8'd31 ;       // match is set to a different value
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;

		/// writing the mask vaule

		addr_or_chnl = 6'h0C;    // write to maskL (0x0C)
		data_byte = 8'h00;       // set mask bits to 00000000 in order to force a non-match
		snd_cmd;
		check_posAck;
		////// Leave all other registers at their default /////
		////// and set RUN bit, but enable AFE first //////
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte = 8'h12;        // set run bit, keep UART triggering on
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		snd_tx;
		//// Now read trig config polling, capture_done should not be set ////
		poll_for_capture_done_no_match(7);
	end

	if (t8) begin
		////////////////////////////////////////////////////////////////////////////
		//// TEST 8: test SPI match with default mask, posedge trigger, 16 bits	////
		////////////////////////////////////////////////////////////////////////////
		initialize;				  // initializes all stimulus to DUT and performs a global reset
		UART_triggering = 0;
		SPI_triggering = 1;		  // using SPI protocol
		en_AFE = 0;				

		pos_edge = 1;			  // positive edge triggering
		width8 = 0;				  // using full 16 bit value 	SPI_tx_data = 16'h8108;

		////// Set for SPI for triggering //////
		op = 2'b01;				  // turn on write mode

		/// Writing the match value 
		matchH = 8'h81;
		matchL = 8'h08;

		SPI_tx_data = 16'h8108;

		addr_or_chnl = 6'h0A;	 // write to matchL (0x0A)
		data_byte = matchL;      // matchL
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h09;	 // write to matchH (0x09)
		data_byte = matchH;      // matchH
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

    	// using default mask values

		////// Leave all other registers at their default /////
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte[5] = 0;         // set capture_done = 0
		data_byte[4] = 1;         // set run bit = 1
		data_byte[3] = pos_edge;  // set SPIedge bit
		data_byte[2] = width8;    // set width bit
		data_byte[1] = 0;         // set SPI disable bit to 0 (SPI is enabled)
		data_byte[0] = 1;         // set UART disable bit to 1
	
    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		snd_tx;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done_match(8);
	end
	
	if (t9) begin
		////////////////////////////////////////////////////////////////////////////////
		//// TEST 9: test  SPI triggering different mask negative edge, only 8 bits ////
		////////////////////////////////////////////////////////////////////////////////
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		UART_triggering = 0;
		SPI_triggering = 1;		// using SPI protocol
		en_AFE = 0;

		pos_edge = 0;			  // negative edge triggering
		width8 = 1;				  // using lower 8 bit value 
		////// Set for SPI for triggering //////
		op = 2'b01;				 // turn on write mode

		/// Writing the match value 
		matchH = 8'hED;          // 1110 1101 
		matchL = 8'h79;			 // 0111 1001 

		SPI_tx_data = 16'hF0D4;  // 1111 0000 1101 0100
	
		addr_or_chnl = 6'h0A;	 // write to matchL (0x0A)
		data_byte = matchL;      // matchL
   		snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h09;	 // write to matchH (0x09)
		data_byte = matchH;      // matchH
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

    	// writing the mask values 
		addr_or_chnl = 6'h0C;	 // write to maskL (0x0C)
		data_byte = 8'h99;       // maskL = 1001 1001
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h0B;	 // write to matchH (0x0B)
		data_byte = 8'hE8;       // maskH = 1110 1000
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		////// Leave all other registers at their default /////
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte[5] = 0;         // set capture_done = 0
		data_byte[4] = 1;         // set run bit = 1
		data_byte[3] = pos_edge;  // set SPIedge bit
		data_byte[2] = width8;    // full 
		data_byte[1] = 0;         // set SPI disable bit to 0 (SPI is enabled)
		data_byte[0] = 1;         // set UART disable bit to 1

    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		snd_tx;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done_match(9);
	end

	if (t10) begin
		//////////////////////////////////////////////////////////////////////////
		//// TEST 10: test SPI triggering with no match triggered on posedge  ////
		//////////////////////////////////////////////////////////////////////////
		initialize;				 // initializes all stimulus to DUT and performs a global reset
		UART_triggering = 0;
		SPI_triggering = 1;		// using SPI protocol
		en_AFE = 0;

		pos_edge = 1;			  // positive edge triggering
		width8 = 0;				  // using lower 8 bit value 

		////// Set for SPI for triggering //////
		op = 2'b01;				 // turn on write mode

		/// Writing the match value 
		matchH = 8'hED;
		matchL = 8'h79;

		SPI_tx_data = 16'hD4F0;
	
		addr_or_chnl = 6'h0A;	 // write to matchL (0x0A)
		data_byte = matchL;      // matchL
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h09;	 // write to matchH (0x09)
		data_byte = matchH;      // matchH
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

   		// writing the mask values 
		addr_or_chnl = 6'h0C;	 // write to maskL (0x0C)
		data_byte = 8'h99;       // maskL = 10011001
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		addr_or_chnl = 6'h0B;	 // write to matchH (0x0B)
		data_byte = 8'hE8;       // maskH = 11101000
    	snd_cmd;				 // send the command, waits for cmd_sent
		check_posAck;

		////// Leave all other registers at their default /////
		addr_or_chnl = 6'h00;	  // write to TrigCfg (0x00)
		data_byte[5] = 0;         // set capture_done = 0
		data_byte[4] = 1;         // set run bit = 1
		data_byte[3] = pos_edge;  // set SPIedge bit
		data_byte[2] = width8;    // full 
		data_byte[1] = 0;         // set SPI disable bit to 0 (SPI is enabled)
		data_byte[0] = 1;         // set UART disable bit to 1

    	snd_cmd;				  // send the command, waits for cmd_sent
		check_posAck;	
		snd_tx;
		//// Now read trig config polling for capture_done bit to be set ////
		poll_for_capture_done_no_match(10);
	end

	if (t11) begin
		////////////////////////////////////////////////////////////////////
		//// TEST 11: ensuring that reset values of cmd_cfg are correct/////
		////////////////////////////////////////////////////////////////////
		initialize;	            // initializes all stimulus to DUT and performs a global reset
		// including the reset of the cmd_cng

		UART_triggering = 0;
		SPI_triggering = 0;
		en_AFE = 0;
		strt_tx = 0;            // do not initiate protocol trigger

		op = 2'b00;				 // turn on read mode

		addr_or_chnl = 6'h00;	 // read from TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[5:0] !== 6'h03) begin
			err = 1;
			$display("Error: TrigCfg (0x00) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h01;	 // read from CH1TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[4:0] !== 5'h01) begin
			err = 1;
			$display("Error: CH1TrigCfg (0x01) does not reset to the proper value.");
		end
		
		addr_or_chnl = 6'h02;	 // read from CH2TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[4:0] !== 5'h01) begin
			err = 1;
			$display("Error: CH2TrigCfg (0x02) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h03;	 // read from CH3TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[4:0] !== 5'h01) begin
			err = 1;
			$display("Error: CH3TrigCfg (0x03) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h04;	 // read from CH4TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[4:0] !== 5'h01) begin
			err = 1;
			$display("Error: CH4TrigCfg (0x04) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h05;	 // read from CH5TrigCfg
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[4:0] !== 5'h01) begin
			err = 1;
			$display("Error: CH5TrigCfg (0x05) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h06;	 // read from Decimator
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp[3:0] !== 4'h0) begin
			err = 1;
			$display("Error: Decimator (0x06) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h07;	 // read from VIH
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'hAA) begin
			err = 1;
			$display("Error: VIH (0x07) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h08;	 // read from VIL
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h55) begin
			err = 1;
			$display("Error: VIL (0x08) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h09;	 // read from MatchH
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h00) begin
			err = 1;
			$display("Error: MatchH (0x09) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0A;	 // read from MatchL
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h00) begin
			err = 1;
			$display("Error: MatchL (0x0A) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0B;	 // read from MaskH
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h00) begin
			err = 1;
			$display("Error: MaskH (0x0B) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0C;	 // read from MaskL
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h00) begin
			err = 1;
			$display("Error: MaskL (0x0C) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0D;	 // read from BaudH
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h06) begin
			err = 1;
			$display("Error: BaudH (0x0D) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0E;	 // read from BaudL
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'hC8) begin
			err = 1;
			$display("Error: BaudL (0x0E) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h0F;	 // read from TrigPosH
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h00) begin
			err = 1;
			$display("Error: TrigPosH (0x0F) does not reset to the proper value.");
		end

		addr_or_chnl = 6'h10;	 // read from TrigPosL
    	snd_cmd;				 // send the command, waits for cmd_sent
		@(posedge resp_rdy);
		if (resp !== 8'h01) begin
			err = 1;
			$display("Error: TrigPosL (0x10) does not reset to the proper value.");
		end

	end

	if (!err)
		$display("Yahoo! All tests passed!");
	$stop();
	 
end

always
  #250 REF_CLK = ~REF_CLK;
  
`include "tb_tasks.txt"

endmodule	

`default_nettype wire

