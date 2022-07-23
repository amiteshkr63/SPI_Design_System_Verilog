/*Notes: SSbar and RD_Wbar has not been implemented yet*/

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

//States
typedef enum {IDLE, TRANSFER, INACTIVE}states;
states PST, NST;
//Debug signals
wire err_ack; 

//CPOL and CPHA 
//CPOL-> 0 -> IDLE at 0 
//		   -> Leading Edge-> Rising Edge**
//CPOL-> 1 -> IDLE at 1 
//		   -> Leading Edge-> Falling Edge**

//CPHA-> 0 -> Sampling at Leading Edge
//		   -> Data change at trailing edge**

//CPHA-> 1 -> Sampling at trailing Edge
//		   -> Data change at leading edge** 
assign w_CPOL= (SPI_MODE==`MODE_POL_PHS_10) | (SPI_MODE==`MODE_POL_PHS_11);
assign w_CPHA= (SPI_MODE==`MODE_POL_PHS_01) | (SPI_MODE==`MODE_POL_PHS_11);

//Internal signals
reg [`WORD_LENGTH-1:0]SPI_BUFFER;
reg  [$clog2(`CLK_PER_HALF_BIT*2-1:0)]SPI_CLK_count;
reg [$clog2(`TOTAL_EDGE_COUNT)-1:0]edge_counter;

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

//PRESENT STATE ASSIGNMENT
	always_ff @(posedge clk or posedge rst) begin : proc_
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
			case ({data_valid, SSbar})
				'b10: NST=TRANSFER;
				'b?1: NST=INACTIVE;
				default : NST=IDLE;
			endcase
		TRANSFER:
			case ({edge_counter==0, SSbar})
				'b?1: NST=INACTIVE;
				'b00: NST=PST;
				'b10: NST=INACTIVE;
			
				default : /* default */;
			endcase
		INACTIVE:
	endcase : PST
end

end
endmodule : spi_master