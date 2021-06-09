
module epcqio_block (
	addr,
	bulk_erase,
	busy,
	clkin,
	data_valid,
	datain,
	dataout,
	illegal_erase,
	illegal_write,
	rden,
	read,
	read_address,
	reset,
	sector_erase,
	shift_bytes,
	wren,
	write,
	asmi_dataout,
	asmi_dclk,
	asmi_scein,
	asmi_sdoin,
	asmi_dataoe);	

	input	[23:0]	addr;
	input		bulk_erase;
	output		busy;
	input		clkin;
	output		data_valid;
	input	[7:0]	datain;
	output	[7:0]	dataout;
	output		illegal_erase;
	output		illegal_write;
	input		rden;
	input		read;
	output	[23:0]	read_address;
	input		reset;
	input		sector_erase;
	input		shift_bytes;
	input		wren;
	input		write;
	input	[3:0]	asmi_dataout;
	output		asmi_dclk;
	output		asmi_scein;
	output	[3:0]	asmi_sdoin;
	output	[3:0]	asmi_dataoe;
endmodule
