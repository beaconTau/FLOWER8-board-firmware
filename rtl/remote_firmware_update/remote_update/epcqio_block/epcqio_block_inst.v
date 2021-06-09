	epcqio_block u0 (
		.addr          (<connected-to-addr>),          //          addr.addr
		.bulk_erase    (<connected-to-bulk_erase>),    //    bulk_erase.bulk_erase
		.busy          (<connected-to-busy>),          //          busy.busy
		.clkin         (<connected-to-clkin>),         //         clkin.clk
		.data_valid    (<connected-to-data_valid>),    //    data_valid.data_valid
		.datain        (<connected-to-datain>),        //        datain.datain
		.dataout       (<connected-to-dataout>),       //       dataout.dataout
		.illegal_erase (<connected-to-illegal_erase>), // illegal_erase.illegal_erase
		.illegal_write (<connected-to-illegal_write>), // illegal_write.illegal_write
		.rden          (<connected-to-rden>),          //          rden.rden
		.read          (<connected-to-read>),          //          read.read
		.read_address  (<connected-to-read_address>),  //  read_address.read_address
		.reset         (<connected-to-reset>),         //         reset.reset
		.sector_erase  (<connected-to-sector_erase>),  //  sector_erase.sector_erase
		.shift_bytes   (<connected-to-shift_bytes>),   //   shift_bytes.shift_bytes
		.wren          (<connected-to-wren>),          //          wren.wren
		.write         (<connected-to-write>),         //         write.write
		.asmi_dataout  (<connected-to-asmi_dataout>),  //  asmi_dataout.asmi_dataout
		.asmi_dclk     (<connected-to-asmi_dclk>),     //     asmi_dclk.asmi_dclk
		.asmi_scein    (<connected-to-asmi_scein>),    //    asmi_scein.asmi_scein
		.asmi_sdoin    (<connected-to-asmi_sdoin>),    //    asmi_sdoin.asmi_sdoin
		.asmi_dataoe   (<connected-to-asmi_dataoe>)    //   asmi_dataoe.asmi_dataoe
	);

