/*Notes: SSbar and RD_Wbar has not been implemented yet*/

//SSbar LOW ->SPI is acting as MASTER
//SSbar HIGH -> SPI chill kr raha h. Mood nhi h DATA transfer krne ka.

`include "globals.vh"
module spi_master (rst_n, clk, data_valid, SPI_status_RDY_BSYbar, 
	/*RD_Wbar,*/ WDATA, RDATA, MOSI, MISO, SCLK, SSbar);

//independent signals
input rst;

//APB related signals
input  clk, data_valid;
/*input [1:0]RD_Wbar;*/
input [`WORD_LENGTH-1:0]WDATA;
output [`WORD_LENGTH-1:0]RDATA;
output SPI_status_RDY_BSYbar;

//SPI slave signals
input MISO;
output SCLK, MOSI, SSbar;

//Internal signals
reg [`WORD_LENGTH-1:0]SPI_BUFFER;
reg  [$clog2(`CLK_PER_HALF_BIT*2-1:0)]SPI_CLK_count;
reg [$clog2(`TOTAL_EDGE_COUNT)-1:0]edge_counter;
reg [$clog2(`WORD_LENGTH)-1:0]data_counter;
reg trailing_edge;
reg leading_edge;
wire handshake;

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

assign w_CPOL= (SPI_MODE==`MODE_POL_PHS_10) | (SPI_MODE==`MODE_POL_PHS_11);
assign w_CPHA= (SPI_MODE==`MODE_POL_PHS_01) | (SPI_MODE==`MODE_POL_PHS_11);
//assign handshake=((SPI_status_RDY_BSYbar==`SPI_READY) & data_valid);

//SCLK Clock Handling
always@(posedge clk, negedge rst) begin
	if(rst) begin
		SCLK<=w_CPOL;										//When rst SCLK is in default state
		edge_counter<=0;	
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

	//Default Assignment
	leading_edge<=0;
	trailing_edge<=0;

	else begin
			if(data_valid==`DATA_VALID) begin
				edge_counter<=`TOTAL_EDGE_COUNT;
			end
			else if (edge_counter>0) begin										//Leading Edge Detection
				if (SPI_CLK_count == `CLK_PER_HALF_BIT -1) begin
					SCLK<=~SCLK;
					SPI_CLK_count<=SPI_CLK_count+'b1;
					edge_counter<=edge_counter-'b1;
					leading_edge<=1;						//Used to tie leading edge with data_handling block(i.e.,data_counter)
				end
				else if (SPI_CLK_count == (`CLK_PER_HALF_BIT*2) -1) begin		//Trailing Edge Detection
					SCLK<=~SCLK;
					SPI_CLK_count<=0;
					edge_counter<=edge_counter-'b1;
					trailing_edge<=1;						//Used to tie trailing edge with data_handling block(i.e.,data_counter)
				end
				else begin
					SPI_CLK_count<=SPI_CLK_count+'b1;
				end
			end
	end 
end

//Data Counter Handling
always_ff @(posedge clk or posedge rst) begin
	if(rst) begin
		data_counter<='d7;
		MOSI<=0;
	end
	else if(SPI_status_RDY_BSYbar==`SPI_READY) begin	//You can't write rst and SPI_status_RDY_BSYbar in one else block. ?????????????? VERIFY
		data_counter<='d7;								// SPI_status_RDY_BSYbar==`SPI_READY it might poosible you have to get Data in MOSI
	end
/*********************************************************************************************************************
IDEA:
	If CPHA--> 0  "DATA will be available on MOSI as soon as data_valid is HIGH" (i.e.,before the leading edge of SCLK)
	If CPHA--> 1  "DATA will be available on MOSI with the SCLK"  (i.e.,with the leading edge of SCLK)
***********************************************************************************************************************/
	else begin
//I need 1 clock delay here for execution of this block. because I want to fill the SPI_BUFF with WDATA. 
//Solution(1):Register the data_valid with r_data_valid. Then, Use r_data_valid in if condition.[e.g., r_data_valid<=data_valid then, use if(data_valid==`DATA_VALID & ~w_CPHA)]
//Solution(2):I am going to use extra state "LOAD" only for loading WDATA in SPI_BUFFER in this code.
		 if((data_valid==`DATA_VALID) & (~w_CPHA) & (PST==TRANSFER)) begin/**************ONE CLOCK DELAY REQUIRED HERE: Solution->(2)****************/
		 	MOSI<=SPI_BUFFER[data_counter];//---------------------------------------------->> USE this in OUTPUT Assignment
		 	data_counter<=data_counter-1;
		 end
/*********************************************************************************************************************
IDEA:
___________________________________________________________________________________________________________________
|	CPOL  |	  CPHA     	|                               DESCRIPTION                                                |
|==================================================================================================================|		
|	0 	  |		0 -------------->	Data is allowed to change at Trailing Edge. So, data_counter is incremented at |
|	1 	  |		0 -------------->	trailing Edge. So, condition is ====>>(trailing_edge & ~w_CPHA)				   |
|==================================================================================================================|
|	1 	  |		0 -------------->	Data is allowed to change at Trailing Edge. So, data_counter is incremented at |
|	1 	  |		1 -------------->	trailing Edge. So, condition is ====>>(trailing_edge & ~w_CPHA)				   |
|==================================================================================================================|	
*********************************************************************************************************************/
		 else if((leading_edge & w_CPHA) | (trailing_edge & ~w_CPHA)) begin//-------------------------------->BEAUTIFUL LINE OF SPI
		 	MOSI<=SPI_BUFFER[data_counter];//----------------------------------------------->>USE this in OUTPUT Assignment
		 	data_counter<=data_counter-1;
		 end
		 else begin
		 	data_counter<=data_counter;
		 end
	end
end

//States
typedef enum {IDLE, LOAD, TRANSFER, INACTIVE}states;
states PST, NST;

//INACTIVE--> In this state, I am sending 8 bits of Received Data from MISO to APB.
//PRESENT STATE ASSIGNMENT
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			 PST<= IDLE;
		end else begin
			 PST<=NST;
		end
	end

//FSM MACHINE
always_comb begin
	case(PST)
		IDLE:	
			if (data_valid) begin
				NST= LOAD;
			end
			else begin
				NST=PST;
			end 
		
		LOAD:
			case ({data_valid, SPI_status_RDY_BSYbar})
			'b10: 		NST=PST;
			'b11: 		NST=TRANSFER;
			default: 	NST=IDLE;;
			endcase
		
		TRANSFER:
			if (data_counter<8) begin
				NST=PST;
			end
			else begin
				NST=INACTIVE;
			end
		
		INACTIVE:
			case ({data_valid, SPI_status_RDY_BSYbar})
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
				{MOSI, SCLK, SSbar} = {1'b0, 1'b0, w_CPOL, `DISCONNECTED_FROM_SLAVE};				//Multiple driver with 58th line of "SCLK Clock Handling block" ----> Think of some solution 
				SPI_status_RDY_BSYbar=`SPI_READY;
		LOAD:
				{MOSI, SCLK, SSbar} = {1'b0, 1'b0, w_CPOL, `DISCONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_READY;
		TRANSFER:
				{MOSI, MISO, SCLK, SSbar} = {1'b0, 1'b0, w_CPOL, `DISCONNECTED_FROM_SLAVE};
				SPI_status_RDY_BSYbar=`SPI_READY;

		INACTIVE:
		default : /* default */;
	endcase

end
endmodule : spi_master