module tb;
	reg rst_n;
	reg clk, apb_ready;
	reg [7:0]WDATA;
	reg MISO;
	wire [7:0]RDATA;
	wire SPI_status_RDY_BSYbar;
	wire rx_data_valid;
	wire SCLK, MOSI, SSbar;

spi_master inst_spi_master
	(
		.rst_n                 (rst_n),
		.clk                   (clk),
		.apb_ready             (apb_ready),
		.SPI_status_RDY_BSYbar (SPI_status_RDY_BSYbar),
		.rx_data_valid         (rx_data_valid),
		.WDATA                 (WDATA),
		.RDATA                 (RDATA),
		.MOSI                  (MOSI),
		.MISO                  (MISO),
		.SCLK                  (SCLK),
		.SSbar                 (SSbar)
	);

	initial	 begin
		$dumpfile("dump.vcd"); $dumpvars;
		{rst_n, clk, apb_ready, WDATA, MISO}=12'b0;
		#10 rst_n =1'b1;
	end
	
	always #5 clk=~clk;

  	always #20 MISO=$random;	
  
      always begin
        #50 {apb_ready, WDATA}=9'b1_1010_1010;
        #10 apb_ready=1'b0;
		#80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
		{apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
        {apb_ready, WDATA}=10'b1_1010_1010;
        #10 apb_ready=1'b0;
        #80;
    end	
  
endmodule
