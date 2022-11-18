/*Notes: SSbar and RD_Wbar has not been implemented yet*/

//SSbar LOW ->SPI is acting as MASTER
//SSbar HIGH -> SPI chill kr raha h. Mood nhi h DATA transfer krne ka.

`include "globals.vh"
module spi_master (rst_n, clk, apb_ready, SPI_status_RDY_BSYbar, 
	/*RD_WR,*/ WDATA, RDATA, MOSI, MISO, SCLK, SSbar);

//independent signals
input rst_n;

//APB related signals
input  clk, apb_ready;
/*input [1:0]RD_WR;*/
input [`WORD_LENGTH-1:0]WDATA;
output reg [`WORD_LENGTH-1:0]RDATA;
output reg SPI_status_RDY_BSYbar;				
output reg rx_data_valid;						//To tell APB that SPI completed Transaction

//SPI slave signals
input MISO;
output reg SCLK, MOSI, SSbar;

//Internal signals
reg [`WORD_LENGTH-1:0]SPI_BUFFER;
reg  [$clog2(`CLK_PER_HALF_BIT*2)-1:0]SPI_CLK_count;
reg [$clog2(`TOTAL_EDGE_COUNT)-1:0]edge_counter;
reg [$clog2(`WORD_LENGTH)-1:0]mosi_data_counter;
reg [$clog2(`WORD_LENGTH)-1:0]miso_data_counter;
reg trailing_edge;
reg leading_edge;
wire [1:0]SPI_MODE;
//wire handshake;

//CPOL and CPHA
wire w_CPOL;
wire w_CPHA;

//Debug signals
wire err_ack; 

//CPOL and CPHA 
//CPOL-> 0 -> IDLE at 0 
//		   -> Leading Edge-> Rising Edge**
//CPOL-> 1 -> IDLE at 1 
//		   -> Leading Edge-> Falling Edge**

//CPHA-> 0 -> Sampling at Leading Edge
//		   -> Data allowed to change at trailing edge**
//CPHA-> 1 -> Sampling at trailing Edge
//		   -> Data allowed to change at leading edge** 

//////////////////////////////////////////////MODE SELECTION//////////////////////////////////////////
assign SPI_MODE=`MODE_POL_PHS_00;
/////////////////////////////////////////////////////////////////////////////////////////////////////

assign w_CPOL= (SPI_MODE==`MODE_POL_PHS_10) | (SPI_MODE==`MODE_POL_PHS_11);
assign w_CPHA= (SPI_MODE==`MODE_POL_PHS_01) | (SPI_MODE==`MODE_POL_PHS_11);
//assign handshake=((SPI_status_RDY_BSYbar==`SPI_READY) & apb_ready);

//SCLK Clock Handling
always_ff@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		SCLK<=w_CPOL;										//When rst_n SCLK is in default state
		edge_counter<=0;	
		leading_edge<=0;
		trailing_edge<=0;
	end
	/**************************************************************************************************************
	IDEA:		
		If Data Valid Start edge counter from 16 because 8 bits of data so we are going to send it over 8 SCLK. 
		so, we are going to have total of 16 EDGES of SCLK	
				If let's say CLK_PER_HALF_BIT=6
				CLK_PER_HALF_BIT*2 -1=11
				CLK_PER_HALF_BIT -1=5
						  6				     6		  					 6				    6
				0 <--------------> 5 <---------------> 11 <==> 0 <--------------> 5 <---------------> 11
	*************************************************************************************************************/
	else begin
		if(apb_ready==`APB_READY) begin
			edge_counter<=`TOTAL_EDGE_COUNT;
		end
		else if (edge_counter>0) begin									//Leading Edge Detection
			if (SPI_CLK_count == `CLK_PER_HALF_BIT -1) begin
				SCLK<=~SCLK;
				SPI_CLK_count<=SPI_CLK_count+'b1;
				edge_counter<=edge_counter-'b1;
				leading_edge<=1;						//Used to tie leading edge with data_handling block(i.e.,mosi_data_counter)
				trailing_edge<=0;
			end
			else if (SPI_CLK_count == (`CLK_PER_HALF_BIT*2) -1) begin	//Trailing Edge Detection
				SCLK<=~SCLK;
				SPI_CLK_count<=0;
				edge_counter<=edge_counter-'b1;
				trailing_edge<=1;						//Used to tie trailing edge with data_handling block(i.e.,mosi_data_counter)
				leading_edge<=0;
			end
			else begin
				SPI_CLK_count<=SPI_CLK_count+'b1;
				leading_edge<=0;
				trailing_edge<=0;
			end
		end
	end 
end

//Tx Data Counter Handling
always_ff @(posedge clk or negedge rst_n) begin
	if(!rst_n && (SPI_status_RDY_BSYbar==`SPI_READY)) begin
		mosi_data_counter<=`WORD_LENGTH-'d1;
	end
/***********************************************************************************************************************************************************************************
IDEA:
	On the MOSI line data will be always available
***********************************************************************************************************************************************************************************/
	else begin
	//I need 1 clock delay here for execution of this block. because I want to fill the SPI_BUFF with WDATA. 
	//Solution(1):Register the apb_ready with r_data_valid. Then, Use r_data_valid in if condition.[e.g., r_data_valid<=apb_ready then, use if(apb_ready==`apb_ready & ~w_CPHA)]
	//Solution(2):I am going to use extra state "LOAD" only for loading WDATA in SPI_BUFFER in this code.
		 if((apb_ready==`APB_READY) & (~w_CPHA) & (PST==TRANSFER)) begin/**************ONE CLOCK DELAY REQUIRED HERE: Solution->(2)****************/
		 	mosi_data_counter<=mosi_data_counter-1;
		 end
/***********************************************************************************************************************************************************************************
IDEA:
________________________________________________________________________________________________________________________
|	CPOL  |	  CPHA     	|                               DESCRIPTION                                                		|
|=======================================================================================================================|		
|	0 	  |		0 -------------->	Data is allowed to change at Trailing Edge. So, mosi_data_counter is incremented at |
|	1 	  |		0 -------------->	trailing Edge. So, condition is ====>>(trailing_edge & ~w_CPHA)				   		|
|=======================================================================================================================|
|	0 	  |		1 -------------->	Data is allowed to change at leading Edge. So, mosi_data_counter is incremented at |
|	1 	  |		1 -------------->	leading Edge. So, condition is ====>>(leading_edge & w_CPHA)				   		|
|=======================================================================================================================|	
***********************************************************************************************************************************************************************************/
		 else if((leading_edge & w_CPHA) | (trailing_edge & ~w_CPHA)) begin//-------------------------------->BEAUTIFUL LINE OF SPI
			mosi_data_counter<=mosi_data_counter-1;
		 end
		 else begin
		 	mosi_data_counter<=mosi_data_counter;
		 end
	end
end

//Rx DATA COUNTER
always_ff @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		miso_data_counter <= `WORD_LENGTH - 'd1;
		rx_data_valid <= 0;
	end else begin
		//Default assignment
		 rx_data_valid <= 0;
		 if (apb_ready == `APB_READY) begin
		 	miso_data_counter <= `WORD_LENGTH - 'd1;
		 end
		 else if ((leading_edge & ~w_CPHA) | (trailing_edge & w_CPHA)) begin
		 	mosi_data_counter <= mosi_data_counter -'d1;
		 end
	end
end

//States
typedef enum {IDLE, LOAD, TRANSFER, INACTIVE}states;
states PST, NST;

//INACTIVE--> In this state, I am sending 8 bits of Received Data from MISO to APB.
//PRESENT STATE ASSIGNMENT
	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			 PST<= IDLE;
		end else begin
			 PST<=NST;
		end
	end

//FSM MACHINE
always_comb begin
	case(PST)
		IDLE:	
			if (apb_ready) begin
				NST=LOAD;
			end
			else begin
				NST=PST;
			end 
		
		LOAD:
			case ({apb_ready, SPI_status_RDY_BSYbar})
			'b10: 		NST=PST;
			'b11: 		NST=TRANSFER;
			default: 	NST=IDLE;
			endcase
		
		TRANSFER:
			if (miso_data_counter<8)  begin  //I am changing state when last bit of spi slave data loaded into SPI Buffer
				NST=PST;						//Verify: If last bit of SPI slave data 
			end
			else begin
				NST=INACTIVE;
			end

		INACTIVE:
			case ({apb_ready, SPI_status_RDY_BSYbar})
				'b01:	NST=IDLE;
				'b11:	NST=LOAD;
				default:NST=PST;
			endcase
endcase
end


//Output Assignments
always_comb begin
	case (PST)
		IDLE:
				{MOSI, SSbar} = {1'b0, `DISCONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_READY;
				RDATA='b0;
				SPI_BUFFER='b0;
				rx_data_valid = 0;
		LOAD:
				{MOSI, SSbar} = {1'b0, `DISCONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_READY;
				SPI_BUFFER=/*RD_WR[0]?*/WDATA/*:'b0*/;
				RDATA='b0;
				rx_data_valid = 0;
/********************************************************************************************************
IDEA:
TRANSFER
========

SSbar=1 (DISCONNECTED FROM SLAVE)
		_________________________					_________________________
		|M7|M6|M5|M4|M3|M2|M1|M0| ---------X--------|S7|S6|S5|S4|S3|S2|S1|S0|
		~~~~~~~~~~~~~~~~~~~~~~~~~					~~~~~~~~~~~~~~~~~~~~~~~~~

SSbar=0 (CONNECTED FROM SLAVE)

Stage-1:
--------
			 _________________________				_________________________
		|----|S7|M6|M5|M4|M3|M2|M1|M0|<<----<<------|M7|S6|S5|S4|S3|S2|S1|S0|<<------|
		|	 ~~~~~~~~~~~~~~~~~~~~~~~~~				~~~~~~~~~~~~~~~~~~~~~~~~~		 |
		|____________________________________________________________________________|

Stage-2:
--------
			 _________________________				_________________________
		|----|S7|S6|M5|M4|M3|M2|M1|M0|<<----<<------|M7|M6|S5|S4|S3|S2|S1|S0|<<------|
		|	 ~~~~~~~~~~~~~~~~~~~~~~~~~				~~~~~~~~~~~~~~~~~~~~~~~~~		 |
		|____________________________________________________________________________|


Stage-3:
--------
			 _________________________				_________________________
		|----|S7|S6|S5|M4|M3|M2|M1|M0|<<----<<------|M7|M6|M5|S4|S3|S2|S1|S0|<<------|
		|	 ~~~~~~~~~~~~~~~~~~~~~~~~~				~~~~~~~~~~~~~~~~~~~~~~~~~		 |
		|____________________________________________________________________________|
										:
										:
										:
										:
Stage-8:
--------
			 _________________________				_________________________
		|----|S7|S6|S5|S4|S3|S2|S1|S0|<<----<<------|M7|M6|M5|M4|M3|M2|M1|M0|<<------|
		|	 ~~~~~~~~~~~~~~~~~~~~~~~~~				~~~~~~~~~~~~~~~~~~~~~~~~~		 |
		|____________________________________________________________________________|

SSbar=1 (DISCONNECTED FROM SLAVE)

*******************************************************************************************************/
		TRANSFER:
				{MOSI, SSbar} = {SPI_BUFFER[mosi_data_counter], `CONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_BUSY;
				SPI_BUFFER[miso_data_counter]=MISO;
				RDATA='b0;
				rx_data_valid=0;
		INACTIVE:
				{MOSI, SSbar} = {1'b0, `DISCONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_BUSY;
				RDATA=/*RD_WR[1]?*/SPI_BUFFER/*:'b0*/;
				rx_data_valid = 1;
//No default condition, check if it is creating any unwanted latch. If yes, in default condition set IDLE's Output assignments.
	endcase

end
endmodule : spi_master
