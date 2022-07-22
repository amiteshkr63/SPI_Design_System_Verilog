`include "globals.vh"
module spi_master (rst_n, clk, data_valid, SPI_status_RDY_BSYbar, 
	/*RD_Wbar,*/ WDATA, RDATA, MOSI, MISO, SCLK, SSbar);

//independent signals
input rst_n;

//APB related signals
input  clk, data_valid;
/*input RD_Wbar;*/
input [7:0]WDATA;
output [7:0]RDATA;
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
//		   -> Data change at trailing edge**

//CPHA-> 1 -> Sampling at trailing Edge
//		   -> Data change at leading edge** 
assign w_CPOL= (SPI_MODE==MODE_POL_PHS_10) | (SPI_MODE==MODE_POL_PHS_11);
assign w_CPHA= (SPI_MODE==MODE_POL_PHS_01) | (SPI_MODE==MODE_POL_PHS_11);

//Internal signals
reg [`WORD_LENGTH-1:0]SPI_BUFFER;
reg  [$clog2(CLK_PER_HALF_BIT*2-1:0)]SPI_CLK_count;

//SCLK Clock Handling
always@(posedge clk, negedge rst_n) begin
	if(~rst) begin
		err_ack<=0;
		SPI_status_RDY_BSYbar<=`SPI_BUSY;

	end
end
	
endmodule : spi_master