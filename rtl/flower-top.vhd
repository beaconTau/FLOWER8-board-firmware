---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      greenland low-threshold trigger using
--               the FLexible Octal WavEform Recorder [FLOWER] Board,
--               Trigger On Phasing [TOP]
-- FILE:         FLOWER-top.vhd
-- AUTHOR:       
-- EMAIL         
-- DATE:         04/2020..
--
-- DESCRIPTION:  board top level
--		
---------------------------------------------------------------------------------

library IEEE; 
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

use work.defs.all;
use work.register_map.all;

entity flower_top is

Generic(
	compile_level	: std_logic_vector(3 downto 0)  := x"0");	
Port(
	--ADC0 data (all LVDS)
	adc0_dA_i		: in std_logic_vector(3 downto 0);
	adc0_dB_i		: in std_logic_vector(3 downto 0);
	adc0_fclk_i		: in std_logic;
	adc0_lclk_i		: in std_logic;
	--ADC1 data (all LVDS)
	adc1_dA_i		: in std_logic_vector(3 downto 0);
	adc1_dB_i		: in std_logic_vector(3 downto 0);
	adc1_fclk_i		: in std_logic;
	adc1_lclk_i		: in std_logic;
	--ADC control/configuration
	adc0_spi_sclk_o	: out std_logic;
	adc0_spi_sdata_o	: out std_logic;
	adc0_spi_csn_o		: out std_logic;
	adc0_spi_resetn_o	: out std_logic;
	adc0_pd_o			: out std_logic;
	adc1_spi_sclk_o	: out std_logic;
	adc1_spi_sdata_o	: out std_logic;
	adc1_spi_csn_o		: out std_logic;
	adc1_spi_resetn_o	: out std_logic;
	adc1_pd_o			: out std_logic;
	--ADC board cal
	cal_pulse_o			: out std_logic;
	cal_sel_o			: out std_logic;
	--pll configuration 
	pll_sda_io			: inout std_logic;
	pll_scl_io			: inout std_logic;
	pll_intrpt_i		: in	std_logic;
	--clocks
	board_clock_i		: in	std_logic; --on-board oscillator
	sys_clock_i			: in	std_logic; --LVDS, from PLL
	--world interfacing
	systrig_i			: in	std_logic; --lvds D12p/E12n
	systrig_o			: out	std_logic; --lvds B12p/A12n, note these are moved in terradaq such that the boards are trying to drive each other
	sync_i				: in	std_logic;
	gpio_sas_io			: inout std_logic_vector(3 downto 0); --gpio(0) is the pps, *gpio(2) is the data-ready interrupt out
	gpio_board_io		: inout std_logic_vector(6 downto 0); --gpios 5 & 6 are on-board LEDs
	biastee_sel_o		: out std_logic_vector(7 downto 0);	
	sma_aux0_io			: out  std_logic;  --*define 0 as output
	sma_aux1_io			: in std_logic;  --*define 1 as input, combined these two will send trigger back and forth, and also do syncing
	usb_uart_rx_i		: in	std_logic; --usb ftdi uart
	usb_uart_tx_o		: out std_logic; --usb ftdi uart
	usb_uart_cts_i		: in	std_logic; --usb ftdi uart
	usb_uart_rts_o		: out	std_logic; --usb ftdi uart
	spi_sclk_i			: in	std_logic; --spi over minisas
	spi_mosi_i			: in	std_logic; --spi over minisas
	spi_miso_o			: out std_logic; --spi over minisas
	spi_cs_i				: in	std_logic);--spi over minisas

end flower_top;

architecture rtl of flower_top is

	---------------------------------------
	--//FIRMWARE DETAILS--
	constant fw_version_maj	: std_logic_vector(7 downto 0)  := x"11"; --start all terra/8channel versions at 16
	constant fw_version_min	: std_logic_vector(7 downto 0)  := x"00";
	constant fw_year			: std_logic_vector(11 downto 0) := x"7E8"; 
	constant fw_month			: std_logic_vector(3 downto 0)  := x"5"; 
	constant fw_day			: std_logic_vector(7 downto 0)  := x"17";
	---------------------------------------
	--//the following signals to/from Clock_Manager--
	--signal clock_internal_10MHz_sys		:	std_logic;
	signal clock_internal_25MHz_sys		:	std_logic;	
	signal clock_internal_10MHz_loc		:	std_logic;
	signal clock_internal_25MHz_loc		:  std_logic;
	signal clock_internal_core				:	std_logic; --*125MHz, presently. derived from system clock
	signal clock_internal_2MHz				:	std_logic;		
	signal clock_internal_1Hz				:	std_logic;		
	signal clock_internal_10Hz				:	std_logic;		
	signal clock_internal_1kHz				:	std_logic;
	signal clock_internal_100kHz			:	std_logic;
	signal pll1_internal_loc				:	std_logic;
	signal pll2_internal_loc				:	std_logic;
	signal serdes_outclk_0					:	std_logic; --test only
	signal serdes_outclk_1					:	std_logic; --test only
	---------------------------------------
	--//internal RESETS --
	signal reset_power_on		:	std_logic;
	---------------------------------------
	--// register i/o
	signal data_to_read_i2c		:	std_logic_vector(23 downto 0);
	signal register_to_read		:	std_logic_vector(define_register_size-1 downto 0);
	signal registers				:	register_array_type; --register space
	signal register_adr			:	std_logic_vector(define_address_size-1 downto 0);
	---------------------------------------
	--// SPI interface
	signal spi_data_pkt_32bit	:	std_logic_vector(31 downto 0);
	signal spi_tx_flag			: 	std_logic;
	signal spi_tx_rdy				:	std_logic;
	signal spi_tx_ack				:	std_logic;
	signal spi_rx_rdy				:	std_logic;
	--signal spi_rx_req			:	std_logic;
	--signal spi_busy				:	std_logic;
	---------------------------------------
	--//data readout signals
	--signal rdout_pckt_size		:	std_logic_vector(15 downto 0);
	signal readout_data				:	std_logic_vector(31 downto 0);
	signal readout_start_flag		:	std_logic;
	signal readout_ram_rd_en		:	std_logic_vector(7 downto 0);
	signal readout_clock				:	std_logic;
	---------------------------------------
	--//fpga temperature sensor
	signal fpga_temp : std_logic_vector(7 downto 0);
	---------------------------------------
	--//remote firmware upgrade signals
	signal remote_upgrade_data 		: 	std_logic_vector(23 downto 0);
	signal remote_upgrade_status		: 	std_logic_vector(23 downto 0);
	signal remote_upgrade_epcq_data 	:  std_logic_vector(31 downto 0);
	signal share_asmi_dataoe			:  std_logic_vector(3 downto 0);
	signal share_asmi_dataout			:  std_logic_vector(3 downto 0);
	signal share_asmi_dclk				:	std_logic;
	signal share_asmi_scein				:  std_logic;
	signal share_asmi_sdoin				:  std_logic_vector(3 downto 0);	
	signal serial_flash_asmi_access_grant_int : std_logic;
	signal serial_flash_asmi_access_req_int  : std_logic;
	---------------------------------------
	--//data management signals
	constant adc_data_parallel_width : integer := 64; --//width of serdes output
	signal adc0_fifo_rdusedw	: std_logic_vector(2 downto 0);
	signal adc1_fifo_rdusedw	: std_logic_vector(2 downto 0);
	signal adc0_data : std_logic_vector(adc_data_parallel_width-1 downto 0) := (others=>'0');
	signal adc1_data : std_logic_vector(adc_data_parallel_width-1 downto 0) := (others=>'0');
	signal rx_fifo_rd : std_logic; --//rd request to adc_receiver fifo
	--//streaming trigger data
	signal ch0_data : std_logic_vector(31 downto 0);
	signal ch1_data : std_logic_vector(31 downto 0);
	signal ch2_data : std_logic_vector(31 downto 0);
	signal ch3_data : std_logic_vector(31 downto 0);
	signal ch4_data : std_logic_vector(31 downto 0);
	signal ch5_data : std_logic_vector(31 downto 0);
	signal ch6_data : std_logic_vector(31 downto 0);
	signal ch7_data : std_logic_vector(31 downto 0);
	signal coinc_trig_scaler_bits : std_logic_vector(17 downto 0); --*moved to 24 bits, previously 12
	signal phased_trig_scaler_bits : std_logic_vector(2*(num_beams+1)-1 downto 0); --*moved to 24 bits, previously 12
	signal trig_scaler_bits:  std_logic_vector(2*(num_beams+1) downto 0); --*moved to 24 bits, previously 12
	signal scaler_to_read_int : std_logic_vector(23 downto 0);
	signal coinc_trig_internal : std_logic;
	signal phased_trig_internal : std_logic ;
	signal phased_trig_bits_metadata : std_logic_vector(num_beams-1 downto 0);
	signal coinc_trig_bits_metadata: std_logic_vector(7 downto 0);
	signal trig_bits_metadata : std_logic_vector(num_beams-1 downto 0);
	--//data chunks
	signal ram_chunked_data : RAM_CHUNKED_DATA_TYPE;
	signal event_metadata : event_metadata_type;
	signal event_manager_status_reg : std_logic_vector(23 downto 0);
	signal event_ram_write_en : std_logic;
	signal event_ram_write_address : std_logic_vector(9 downto 0);
	--//timestamps
	signal latched_timestamp : std_logic_Vector(47 downto 0);
	--//pps
	signal internal_delayed_pps : std_logic := '0';
	signal internal_pps_cycle_counter : std_logic_vector(47 downto 0);
	signal internal_sync_out : std_logic;
	signal internal_pps_fast_sync_flag : std_logic;
	signal internal_sma_trigger_input_assign : std_logic;
	signal internal_sma_sync_input_assign : std_logic;
	signal internal_coinc_trig_to_out_sma_en : std_logic := '0';
	signal internal_phased_trig_to_out_sma_en : std_logic := '0';
	signal internal_event_write_busy : std_logic := '0'; --flag if busy writing event to ram, or buffer still full

	---------------------------------------
	--//altera active-serial loader (for jtag->serial flash programming)
	--// extra complicated due to also having remote update -- needs to share asmi interface
	component serial_flash
		port( 
		noe_in 			: in std_logic;
		dclk_in			: in std_logic;
		ncso_in			: in std_logic;
		asmi_access_granted : in std_logic;
		asmi_access_request : out std_logic;
		data_in	      : in std_logic_vector(3 downto 0);
		data_oe 			: in std_logic_vector(3 downto 0);
		data_out			: out std_logic_Vector(3 downto 0));
	end component;
	---------------------------------------
	component signal_sync is
	port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
	end component;

begin
	systrig_o <= 'Z'; --this will break compile for flower/radiant setup, only for 2-flower terradaq
	
	--//test LED
	gpio_board_io(5) <= gpio_sas_io(0); --clock_internal_1Hz;
	gpio_board_io(6) <= clock_internal_10Hz;
	--//send local 10MHz out on gpio(0)
	gpio_board_io(0) <= board_clock_i;
	--///////////////////////////////////////
	--//resets
	xRESETS : entity work.reset_and_startup
	port map(
		clk_i	 			=> clock_internal_2MHz,	
		power_on_rst_o	=> reset_power_on);	
	--///////////////////////////////////////
	-----------------------------------------
	--//serial flash
	xSERIALFLASH : serial_flash
	port map(
		noe_in 			=> '0',
		dclk_in			=> share_asmi_dclk,
		ncso_in			=> share_asmi_scein, 
		asmi_access_granted => serial_flash_asmi_access_grant_int,
		asmi_access_request => serial_flash_asmi_access_req_int,
		data_in	      => share_asmi_sdoin,
		data_oe 			=> share_asmi_dataoe,
		data_out			=> share_asmi_dataout);
	proc_share_asmi : process(clock_internal_25MHz_loc)
	begin
		if rising_edge(clock_internal_25MHz_loc) then
			if registers(110)(0) = '1' then --remote upgrade block gets access to asmi interface
				serial_flash_asmi_access_grant_int<= '0';
			elsif serial_flash_asmi_access_req_int = '1' then
				serial_flash_asmi_access_grant_int <= '1';
			elsif serial_flash_asmi_access_req_int = '0' then
				serial_flash_asmi_access_grant_int <= '0';
			else
				serial_flash_asmi_access_grant_int <= '0';
			end if;
		end if;
	end process;
	--///////////////////////////////////////
	-----------------------------------------
	--//clocks
	xCLOCKS : entity work.clock_manager
	port map(
		Reset_i			=> reset_power_on,
		CLK0_i			=> board_clock_i,
		CLK1_i			=> sys_clock_i,
		PLL_reset_i		=>	'0',--clock_FPGA_PLLrst,		
		CLK_2MHz_o		=> clock_internal_2MHz,		
		CLK_10MHz_loc_o=> clock_internal_10MHz_loc, 
		CLK_25MHz_loc_o=> clock_internal_25MHz_loc,
		CLK_25MHz_sys_o=> clock_internal_25MHz_sys, --clock_internal_10MHz_sys,
		CLK_core_sys_o => clock_internal_core, --//*125MHz at the moment
		CLK_1Hz_o		=> clock_internal_1Hz,
		CLK_10Hz_o		=> clock_internal_10Hz,
		CLK_1kHz_o		=> clock_internal_1kHz,	
		CLK_100kHz_o	=> clock_internal_100kHz,
		fpga_pll1lock_o => pll1_internal_loc,
		fpga_pll2lock_o => pll2_internal_loc);
	--///////////////////////////////////////
	-----------------------------------------
	--//readout controller using Beaglebone
	xREADOUT_CONTROLLER : entity work.readout_controller
	port map(
		rst_i						=> reset_power_on,
		clk_i						=> clock_internal_25MHz_loc,
		rdout_reg_i				=> register_to_read,  --//read register
		reg_adr_i				=> register_adr,
		registers_i				=> registers,         
		tx_rdy_o					=> spi_tx_flag, 
		--tx_rdy_spi_i			=> spi_tx_rdy,
		tx_ack_i					=> spi_tx_ack,
		tx_rdy_spi_i			=> '0', --newer spi_slave code
		rdout_fpga_data_o		=> readout_data);
	--///////////////////////////////////////	
	-----------------------------------------
	--//EVENT DATA MANAGER
	xDATA_MANAGER : entity work.data_manager
	port map(
		rst_i			=> reset_power_on,
		clk_i			=> clock_internal_25MHz_loc, --clock_internal_10MHz_loc,
		clk_data_i	=> clock_internal_core,
		registers_i	=> registers,
		coinc_trig_i=> coinc_trig_internal,
		phase_trig_i=> phased_trig_internal, --exists :)
		ext_trig_i	=> internal_sma_trigger_input_assign, --(sma_aux1_io and (not registers(99)(1))), --use SMA1 for ext trig input. If assigned as secondary board in sync scheme, ignore
		pps_i			=> internal_delayed_pps, --gpio_sas_io(0), 
		coinc_trig_bits_metadata_i => coinc_trig_bits_metadata,
		phased_trig_bits_metadata_i => phased_trig_bits_metadata,
		dat_rdy_o	=> gpio_sas_io(2),
		event_write_busy_o => internal_event_write_busy,
		latched_timestamp_o  => latched_timestamp,
		status_reg_o	 => event_manager_status_reg,
		ram_write_o		 => event_ram_write_en,
		ram_write_adr_o => event_ram_write_address,	
		evt_meta_o		 => event_metadata		);
	--///////////////////////////////////////	
	-----------------------------------------
	--//REGISTERS
	xREGISTERS : entity work.registers_spi
	port map(
		rst_powerup_i			=> reset_power_on,
		rst_i						=> reset_power_on,
		clk_i						=> clock_internal_25MHz_loc, --clock_internal_10MHz_loc,  --//clock for register interface
		-----------------------------
		--//status/read-only registers
		firmware_date_i					=> fw_year & fw_month & fw_day,
		firmware_ver_i						=> x"00" & fw_version_maj & fw_version_min, 
		i2c_read_reg_i						=> data_to_read_i2c,
		fpga_temp_i							=> (others=>'0'), --fpga_temp,
		scaler_to_read_i 					=> scaler_to_read_int, --scaler_to_read,
		status_data_manager_i 			=> event_manager_status_reg,
		status_data_manager_surface_i	=> (others=>'0'), --status_reg_data_manager_surface,
		status_data_manager_latched_i => (others=>'0'), --status_reg_latched_data_manager,
		status_adc_i	 					=> (others=>'0'), --status_reg_adc,
		event_metadata_i 					=> event_metadata, --event_meta_data,
		current_ram_adr_data_i 			=> ram_chunked_data, --ram_data,
		current_ram_adr_data_surface_i=> (others=>(others=>'0')), 
		remote_upgrade_data_i			=> x"00" & remote_upgrade_data, --remote_upgrade_data,	
		remote_upgrade_epcq_data_i		=> remote_upgrade_epcq_data, --remote_upgrade_epcq_data,
		remote_upgrade_status_i			=> "0000000" & serial_flash_asmi_access_grant_int & remote_upgrade_status(15 downto 0), --remote_upgrade_status,
		pps_timestamp_to_read_i			=> latched_timestamp,
		-----------------------------
		write_reg_i		=> spi_data_pkt_32bit,
		write_rdy_i		=> spi_rx_rdy,
		read_reg_o 		=> register_to_read,
		registers_io	=> registers, --//system register space
		sync_i 			=> internal_sma_sync_input_assign,
		sync_o			=> internal_sync_out,
		address_o		=> register_adr);	
	--///////////////////////////////////////	
	-----------------------------------------
	--//PC interface SPI comms.:
	xPCINTERFACE : entity work.cpu_interface
	port map(
		clk_i			 => clock_internal_25MHz_loc, --clock_internal_10MHz_loc,
		rst_i			 => reset_power_on,
		spi_cs_i	 	 => spi_cs_i,	
		spi_sclk_i	 => spi_sclk_i,	
		spi_mosi_i	 => spi_mosi_i,	
		spi_miso_o	 => spi_miso_o,
		data_i		 => readout_data,
		tx_load_i	 => spi_tx_flag,
		data_o   	 => spi_data_pkt_32bit,
		--rx_req_i		 => spi_rx_req,
		--spi_busy_o	 => spi_busy,
		tx_ack_o		 => spi_tx_ack,
		rx_rdy_o		 => spi_rx_rdy);
	--///////////////////////////////////////	
	-----------------------------------------
	--//interface to i2c via SPI (pll programming for this project):		
	xSPI_I2C_BRIDGE : entity work.spi_to_i2c_bridge
	port map(
		reset_i		 => reset_power_on,	
		clk_i			 => clock_internal_25MHz_loc, --clock_internal_10MHz_loc,		
		registers_i  => registers, 	
		address_i	 => register_adr,	
		i2c_read_o	 => data_to_read_i2c,	
		sda_io       => pll_sda_io,
		scl_io       => pll_scl_io);
	--///////////////////////////////////////	
	-----------------------------------------
	--//hmcad151x configuration:		
	xADC_CONTROL : entity work.adc_controller
	port map(
		rst_i => reset_power_on, 	clk_i	=> clock_internal_25MHz_loc,			
		registers_i	=> registers, 	reg_addr_i => register_adr,
		sdat0_o => adc0_spi_sdata_o, sclk0_o => adc0_spi_sclk_o,	
		csn0_o => adc0_spi_csn_o, rstn0_o=>adc0_spi_resetn_o, pd0_o	=> adc0_pd_o,		
		sdat1_o => adc1_spi_sdata_o, sclk1_o => adc1_spi_sclk_o,	
		csn1_o => adc1_spi_csn_o, rstn1_o=>adc1_spi_resetn_o, pd1_o	=> adc1_pd_o,
		rx_adc0_data_i		=> adc0_data,  
		rx_adc1_data_i		=> adc1_data,
		rx_fifo_rd_en_o	=> rx_fifo_rd,
		rx_fifo_usedwrd_i	=> adc0_fifo_rdusedw,
		clk_data_i 			=> clock_internal_core,
		ram_write_en_i 	=> event_ram_write_en,
		ram_write_adr_i	=> event_ram_write_address,
		adc_ram_data_o		=> ram_chunked_data,
		ch0_datastream_o  => ch0_data ,  --to trigger block
		ch1_datastream_o  => ch1_data ,
		ch2_datastream_o  => ch2_data ,
		ch3_datastream_o  => ch3_data ,
		ch4_datastream_o  => ch4_data ,  --to trigger block
		ch5_datastream_o  => ch5_data ,
		ch6_datastream_o  => ch6_data ,
		ch7_datastream_o  => ch7_data );		
	--///////////////////////////////////////	
	-----------------------------------------
	--//hmcad151x data-flow:			
	xADC0_DATA_RX : entity work.adc_receiver
	generic map(adc_data_parallel_width)
	port map(
		rst_i => reset_power_on, clk_i=> clock_internal_core, clk_reg_i => clock_internal_25MHz_loc,
		registers_i	=> registers,
		adc_dA_i	=> adc0_dA_i,   	adc_dB_i => adc0_dB_i,
		adc_fclk_i => adc0_fclk_i, adc_lclk_i => adc0_lclk_i, serdes_clk_o => serdes_outclk_0,
		rx_fifo_rdusedw_o => adc0_fifo_rdusedw,
		rx_fifo_rd_i		=> rx_fifo_rd,
		rx_adc_data_o 		=> adc0_data);
	xADC1_DATA_RX : entity work.adc_receiver
	generic map(adc_data_parallel_width)
	port map(
		rst_i => reset_power_on, clk_i=> clock_internal_core, clk_reg_i => clock_internal_25MHz_loc,
		registers_i	=> registers,
		adc_dA_i	=> adc1_dA_i,   	adc_dB_i => adc1_dB_i,
		adc_fclk_i => adc1_fclk_i, adc_lclk_i => adc1_lclk_i, serdes_clk_o => serdes_outclk_1,
		rx_fifo_rdusedw_o => adc1_fifo_rdusedw,
		rx_fifo_rd_i		=> rx_fifo_rd,	
		rx_adc_data_o 		=> adc1_data);
	--///////////////////////////////////////	
	-----------------------------------------
	--systrig_o   <= (coinc_trig_internal and registers(92)(0)) or (internal_delayed_pps and registers(92)(8)); 
	systrig_o   <= '0'; -- don't use differential output over mini-sas
	-----------------------------------------
	-----------------------------------------
	
	proc_assign_sma_output : process(registers(99)(0))
	begin
	case registers(99)(0) is
		when '1' =>
			sma_aux0_io <= internal_sync_out;
		when '0' => 
			--add logic with the event_write_busy, so that secondary board doesn't keep getting triggers while the event is being written
			sma_aux0_io <= phased_trig_internal and (internal_coinc_trig_to_out_sma_en or internal_phased_trig_to_out_sma_en)  and (not internal_event_write_busy);
	end case;
	end process;
	
	proc_assign_sma_input : process(registers(99)(1))
	begin
	case registers(99)(1) is
		when '1' =>
			internal_sma_trigger_input_assign <= '0'; --ignore if assigned as secondary board in sync-mode
			internal_sma_sync_input_assign <= sma_aux1_io;
		when '0' => 
			internal_sma_trigger_input_assign <= sma_aux1_io;
			internal_sma_sync_input_assign <= '0';
	end case;
	end process;
	-----------------------------------------
	-----------------------------------------	
	xCOINC_TRIG_OUTPUT_EN : signal_sync
	port map(
	clkA	=> clock_internal_25MHz_loc, clkB => clock_internal_core,
	SignalIn_clkA	=> registers(96)(0), 
	SignalOut_clkB	=>  internal_coinc_trig_to_out_sma_en);
	
	xPHASED_TRIG_OUTPUT_EN : signal_sync
	port map(
	clkA	=> clock_internal_25MHz_loc, clkB => clock_internal_core,
	SignalIn_clkA	=> registers(96)(0), 
	SignalOut_clkB	=> internal_phased_trig_to_out_sma_en);
	-----------------------------------------
	-----------------------------------------
	xCOINC_TRIG : entity work.simple_trigger
	port map(
		rst_i			=> reset_power_on,
		clk_i			=> clock_internal_25MHz_loc,
		clk_data_i	=> clock_internal_core,
		registers_i	=> registers,
		ch0_data_i	=> ch0_data,
		ch1_data_i	=> ch1_data, 
		ch2_data_i	=> ch2_data, 
		ch3_data_i	=> ch3_data,
		ch4_data_i	=> ch4_data,
		ch5_data_i	=> ch5_data, 
		ch6_data_i	=> ch6_data, 
		ch7_data_i	=> ch7_data,
		last_trig_bits_latched_o => coinc_trig_bits_metadata,
		trig_bits_o => coinc_trig_scaler_bits,
		coinc_trig_o=> coinc_trig_internal);
	-----------------------------------------
	-----------------------------------------
	xPHASED_TRIG : entity work.phased_trigger
	port map(
		rst_i			=> reset_power_on,
		clk_i			=> clock_internal_25MHz_loc,
		clk_data_i	=> clock_internal_core,
		registers_i	=> registers,
		ch0_data_i	=> ch0_data,
		ch1_data_i	=> ch1_data, 
		ch2_data_i	=> ch2_data, 
		ch3_data_i	=> ch3_data,
		ch4_data_i	=> ch4_data,
		ch5_data_i	=> ch5_data, 
		ch6_data_i	=> ch6_data, 
		ch7_data_i	=> ch7_data,
		last_trig_bits_latched_o => phased_trig_bits_metadata,
		trig_bits_o => phased_trig_scaler_bits,
		phased_trig_o=> phased_trig_internal);
	-----------------------------------------
	-----------------------------------------
	xGLOBAL_TIMING : entity work.pps_timing
	port map(
		rst_i			=> reset_power_on,
		clk_i			=> clock_internal_25MHz_loc, --clock_internal_10MHz_loc, 
		clk_10MHz_i	=> clock_internal_25MHz_sys,
		clk_data_i	=> clock_internal_core,
		registers_i	=> registers,
		pps_i			=>	gpio_sas_io(0),
		pps_o			=> internal_delayed_pps,
		pps_fast_flag_o => internal_pps_fast_sync_flag,
		pps_cycle_counter_o => internal_pps_cycle_counter); 
	-----------------------------------------
	xSCALERS : entity work.scalers_top
	port map(
		rst_i					=> reset_power_on,
		clk_i					=> clock_internal_25MHz_loc, --clock_internal_10MHz_loc,
		gate_i					=> gpio_sas_io(0), --pps from controller
		reg_i						=> registers,
		coinc_trig_bits_i 	=> coinc_trig_scaler_bits,
		phased_trig_bits_i 	=> phased_trig_scaler_bits,
		pps_cycle_counter_i	=> internal_pps_cycle_counter,
		scaler_to_read_o  => scaler_to_read_int);
	--///////////////////////////////////////	
	-----------------------------------------
	--//pulse from FPGA to RF input switches for ADC alignment
	xCALPULSE : entity work.calpulse	
	port map(
		rst_i		=> reset_power_on,
		clk_reg_i=> clock_internal_25MHz_loc,	
		clk_i		=> clock_internal_core,		
		reg_i		=> registers,	
		pulse_o	=> cal_pulse_o,
		pps_fast_sync_i => internal_pps_fast_sync_flag,
		rf_switch_o => cal_sel_o); --//when cal_sel_o = 1 ==> signal path	
	-----------------------------------------
	--///////////////////////////////////////
	--REMOTE FIRMWARE UPGRADE
	xREMOTE_FIRMWARE_UPGRADE :  entity work.remote_firmware_update_top
	port map(
		rst_i				=> reset_power_on,	
		clk_10MHz_i		=> clock_internal_10MHz_loc, --clock_internal_10MHz_loc,
		clk_i				=> clock_internal_25MHz_loc, --clock_internal_10MHz_loc, --// register clock
		registers_i		=> registers,
		stat_reg_o		=> remote_upgrade_status,
		epcq_rd_data_o => remote_upgrade_epcq_data,
		data_o			=> remote_upgrade_data,
		asmi_dataoe_o 	=> share_asmi_dataoe,
		asmi_dataout_i	=> share_asmi_dataout,
		asmi_dclk_o		=> share_asmi_dclk,
		asmi_scein_o	=> share_asmi_scein,
		asmi_sdoin_o	=> share_asmi_sdoin);
	-----------------------------------------
end rtl;
