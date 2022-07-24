/*Notes: SSbar and RD_Wbar has not been implemented yet*/

//SSbar LOW ->SPI is acting as MASTER
//SSbar HIGH -> SPI chill kr raha h. Mood nhi h uska kaam krne ka.

`include "globals.vh"
module spi_master (rst_n, clk, data_valid, SPI_status_RDY_BSYbar, 
	/*RD_Wbar,*/ WDATA, RDATA, MOSI, MISO, SCLK, SSbar);

//independent signals
input rst;

//APB related signals
input  clk, data_valid;
/*input RD_Wbar;*/
input [`WORD_LENGTH-1:0]WDATA;
output [`WORD_LENGTH-1:0]RDATA;
output SPI_status_RDY_BSYbar;

//SPI slave signals
input MISO;
output SCLK, MOSI, SSbar;

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

//Internal signals
reg [`WORD_LENGTH-1:0]SPI_BUFFER;
reg  [$clog2(`CLK_PER_HALF_BIT*2-1:0)]SPI_CLK_count;
reg [$clog2(`TOTAL_EDGE_COUNT)-1:0]edge_counter;
reg [$clog2(`WORD_LENGTH)-1:0]data_counter;

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
						  6				     6		  					6				     6
				0 <--------------> 5 <---------------> 11 <==> 0 <--------------> 5 <---------------> 11

	*************************************************************************************************************/
	else begin
			if(data_valid) begin
				edge_counter<=`TOTAL_EDGE_COUNT;
			end
			else if (edge_counter>0) begin
				if (SPI_CLK_count == (`CLK_PER_HALF_BIT*2) -1) begin
					SCLK<=~SCLK;
					SPI_CLK_count<=0;
					edge_counter<=edge_counter-'b1;
				end
				else if (SPI_CLK_count == `CLK_PER_HALF_BIT -1) begin
					SCLK<=~SCLK;
					SPI_CLK_count<=SPI_CLK_count+'b1;
					edge_counter<=edge_counter-'b1;
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
		data_counter<=0;
		MOSI<=0;
	end
	else if(SPI_status_RDY_BSYbar==`SPI_READY) begin	//You can't write rst and SPI_status_RDY_BSYbar in one else block. ?????????????? VERIFY
		data_counter<=0;								// SPI_status_RDY_BSYbar==`SPI_READY it might poosible you have to get Data in MOSI
	end
/*********************************************************************************************************************
IDEA:
	If CPHA--> 0  "DATA will be available on MOSI as soon as data_valid is HIGH" (i.e.,before the leading edge of SCLK)
	If CPHA--> 1  "DATA will be available on MOSI with the SCLK"  (i.e.,with the leading edge of SCLK)
***********************************************************************************************************************/
	else begin
		 <= ;
	end
end

//States
typedef enum {IDLE, ACTIVE, TRANSFER, INACTIVE}states;
states PST, NST;

//PRESENT STATE ASSIGNMENT
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			 PST<= IDLE;
		end else begin
			 PST<=NST;
		end
	end

//FSM MACHINE
always_comb begin begin
	case(PST)
		
		IDLE:	
			if (data_valid) begin
				NST= ACTIVE;
			end
			else begin
				NST=PST;
			end 
		
		ACTIVE:
			case ({data_valid, SSbar})
				'b10: NST=TRANSFER;
				'b11: NST=PST;
				default : NST=IDLE;
			endcase
		
		TRANSFER:
			case ({data_counter<8, SSbar})
				'b10: NST=PST;
				'b00: NST=INACTIVE;		
				default : NST=IDLE;
			endcase
		
		INACTIVE:
			if (data_valid) begin
				NST=ACTIVE;
			end
			else begin
				NST=IDLE;
			end
endcase
end

//Output Assignments
always_comb begin
	case (PST)
		IDLE:
		ACTIVE:
		TRANSFER:
		INACTIVE:
		default : /* default */;
	endcase

end
endmodule : spi_master