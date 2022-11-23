`include "globals.vh"
module spi_master (rst_n, clk, apb_ready, SPI_status_RDY_BSYbar, rx_data_valid, WDATA, RDATA, MOSI, MISO, SCLK, SSbar);

//independent signals
input rst_n;

//APB related signals
input  clk, apb_ready;
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
reg [$clog2(`TOTAL_EDGE_COUNT):0]edge_counter;
reg [$clog2(`WORD_LENGTH)-1:0]mosi_data_counter;
reg trailing_edge;
reg leading_edge;
wire [1:0]SPI_MODE;
reg r_apb_ready;
reg r1_apb_ready;

//CPOL and CPHA
wire w_CPOL;
wire w_CPHA;

//States
typedef enum {IDLE, TRANSFER}states;
states PST, NST;

/**/////////////////////////////////////////////MODE SELECTION///////////////////////////////////////////**/																									//
/**/								assign SPI_MODE=`MODE_POL_PHS_00;									/**/																									//
/**//////////////////////////////////////////////////////////////////////////////////////////////////////**/

assign w_CPOL= (SPI_MODE==`MODE_POL_PHS_10) | (SPI_MODE==`MODE_POL_PHS_11);
assign w_CPHA= (SPI_MODE==`MODE_POL_PHS_01) | (SPI_MODE==`MODE_POL_PHS_11);

always_ff@(posedge clk or negedge rst_n) begin
	if (!rst_n)	begin 
		r_apb_ready<=0;
		r1_apb_ready<=0;
	end
	else begin
		r1_apb_ready<=r_apb_ready;
		r_apb_ready<=apb_ready;
	end
end

//SCLK Clock Handling
always_ff@(posedge clk or negedge rst_n) begin
	if((!rst_n) || (PST==IDLE)  || ((edge_counter=='d0) && (apb_ready || r1_apb_ready) && (PST==TRANSFER)) ) begin
		SCLK<=w_CPOL;									//When rst_n SCLK is in default state
		SPI_CLK_count<=0;
		edge_counter<=`TOTAL_EDGE_COUNT;	
		leading_edge<=0;
		trailing_edge<=0;
	end
	else begin
/*		if (mosi_data_counter=='d7) begin
			edge_counter<=`TOTAL_EDGE_COUNT-'d1;
			if (apb_ready) begin
				SCLK=~SCLK;
				SPI_CLK_count<=SPI_CLK_count+'b1;
				edge_counter<=`TOTAL_EDGE_COUNT-'d1;
				leading_edge<=~w_CPHA;
				trailing_edge<=w_CPHA;		
			end
		end
		else */if (edge_counter>0) begin						//Leading Edge Detection
			if (SPI_CLK_count == (`CLK_PER_HALF_BIT -'b1)) begin
				SCLK<=~SCLK;
				SPI_CLK_count<=SPI_CLK_count+'b1;
				edge_counter<=edge_counter-'b1;
				leading_edge<=1;						//Used to tie leading edge with data_handling block(i.e.,mosi_data_counter)
				trailing_edge<=0;
			end
			else if (SPI_CLK_count == ((`CLK_PER_HALF_BIT*2) -'b1)) begin	//Trailing Edge Detection
				SCLK<=~SCLK;
				SPI_CLK_count<=0;
				edge_counter<=edge_counter-'b1;
				trailing_edge<=1;						//Used to tie trailing edge with data_handling block(i.e.,mosi_data_counter)
				leading_edge<=0;
			end
			else begin
				SPI_CLK_count<=SPI_CLK_count+1'b1;
				leading_edge<=0;
				trailing_edge<=0;
			end
		end
	end 
end

//Tx Data Counter Handling
always_comb begin
	if((!rst_n) | (SPI_status_RDY_BSYbar==`SPI_READY)) begin
		mosi_data_counter<=`WORD_LENGTH-'d1;
	end
	else if((leading_edge & w_CPHA) | (trailing_edge & ~w_CPHA)) begin 	//->BEAUTIFUL LINE OF SPI
			mosi_data_counter<=mosi_data_counter-1;
		 end
	else begin
	 	mosi_data_counter<=mosi_data_counter;
	end
end

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
			begin	
				if (apb_ready) begin
					NST=TRANSFER;
				end
				else begin
					NST=PST;
				end 
			end
		TRANSFER:
			begin
				if (!edge_counter && !(apb_ready || r1_apb_ready)) begin
					NST=IDLE;
				end
				else NST=PST;
			end
/*		TRANSFER:
			begin
				if(!edge_counter)begin
					if (apb_ready || r1_apb_ready) begin
						NST=PST;
					end
					else	NST=IDLE;
				end
				else begin
					NST=PST;
				end
			end*/
	endcase
end

//Output Assignments
always_comb begin
	case (PST)
		IDLE:
			begin
				if (!apb_ready) begin
					{MOSI, SSbar} = {SPI_BUFFER[`WORD_LENGTH-'d1], `DISCONNECTED_FROM_SLAVE};
					SPI_status_RDY_BSYbar=`SPI_READY;
					RDATA='b0;
					SPI_BUFFER='b0;///////////////////////////////////////////////
					rx_data_valid = 0;
				end
				else begin
					{MOSI, SSbar} = {SPI_BUFFER[`WORD_LENGTH-'d1], `DISCONNECTED_FROM_SLAVE};
					SPI_status_RDY_BSYbar=`SPI_READY;
					SPI_BUFFER=WDATA;///////////////////////////////////////////
					RDATA='b0;
					rx_data_valid = 0;
				end
			end
	
		TRANSFER:
			begin
				SPI_status_RDY_BSYbar=`SPI_BUSY;
				//if(((mosi_data_counter=='b0) && (SPI_CLK_count=='d3) && apb_ready))begin
				if((!edge_counter) && (apb_ready))begin
					SPI_BUFFER=WDATA;////////////////////////////////////////
				end
				else if ((leading_edge & w_CPHA) || (trailing_edge & ~w_CPHA)) begin
					{MOSI, SSbar} = {SPI_BUFFER[mosi_data_counter], `CONNECTED_FROM_SLAVE};
					RDATA='b0;
					rx_data_valid=0;
				end	
				else if((leading_edge & ~w_CPHA) || (trailing_edge & w_CPHA)) begin
					SPI_BUFFER[mosi_data_counter]=MISO;
				end
			end
	endcase
end
endmodule
