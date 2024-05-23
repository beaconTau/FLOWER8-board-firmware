---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         adc_controller.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         1/2021
--
-- DESCRIPTION:  slow control/config of hmcad1511 + data alignment
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity adc_controller is
	generic(
		adc_data_parallel_width : integer := 64;
		--//ADC select register
		adc_config_reg_adr_0	: std_logic_vector(7 downto 0):= x"3B"; 
		--//24-bit configuration word (8bit addr + 16bit message) register
		adc_config_reg_adr_1	: std_logic_vector(7 downto 0):= x"3C";
		--//ADC PD control register
		adc_pd_reg_adr       : std_logic_vector(7 downto 0):= x"3A";
		--//sample-align registers
		adc0_sample_shift_adr: std_logic_vector(7 downto 0):= x"38";
		adc1_sample_shift_adr: std_logic_vector(7 downto 0):= x"39";
		--FPGA RAM rad address register
		ram_read_adr_reg_adr : std_logic_vector(7 downto 0):= x"45";
		--FPGA RAM select register
		ram_select_reg_adr   : std_logic_vector(7 downto 0):= x"41";
		--//bitshift register
		bitshift_reg_adr		: std_logic_vector(7 downto 0):= x"42";
		--//pretrig register
		pretrig_reg_adr		: std_logic_vector(7 downto 0):= x"4C";
		--SW trigger
		software_trigger_reg_adr :  std_logic_vector(7 downto 0):= x"40");
	port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 
		clk_data_i	:	in		std_logic; --data clock
		registers_i	:	in		register_array_type;
		reg_addr_i	:  in    std_logic_vector(define_address_size-1 downto 0);
		--//control lines for ADC0
		sdat0_o		:	out	std_logic;
		sclk0_o		:	out	std_logic;
		csn0_o		: 	out	std_logic;
		rstn0_o		: 	out	std_logic;
		pd0_o			: 	out	std_logic;
		--//control lines for ADC1		
		sdat1_o		:	out	std_logic;
		sclk1_o		:	out	std_logic;
		csn1_o		: 	out	std_logic;
		rstn1_o		: 	out	std_logic;
		pd1_o			: 	out	std_logic;
		--//fifo management
		rx_adc0_data_i		:  in  std_logic_vector(adc_data_parallel_width-1 downto 0); --adc0
		rx_adc1_data_i		:  in  std_logic_vector(adc_data_parallel_width-1 downto 0); --adc1
		rx_fifo_rd_en_o   :	out std_logic;
		rx_fifo_usedwrd_i	:	in	 std_logic_vector(2 downto 0);
		--//write ram control from data manager
		ram_write_en_i 	: in std_logic;
		ram_write_adr_i	: in std_logic_vector(9 downto 0);
		--//output wfm data
		adc_ram_data_o		:  out RAM_CHUNKED_DATA_TYPE; --//data in RAM
		ch0_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch1_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch2_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch3_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch4_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch5_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch6_datastream_o	:	out std_logic_vector(31 downto 0); --streaming data to trig block
		ch7_datastream_o	:	out std_logic_vector(31 downto 0)  --streaming data to trig block
		);
		
end adc_controller;

architecture rtl of adc_controller is
----------------------------------------------------------
--slow config signals
type write_config_state_type is (idle, write_reg);
signal write_config_state : write_config_state_type;
signal internal_sclk	: 	std_logic;
signal internal_sdat 	: 	std_logic;
signal internal_csn	:	std_logic;
signal internal_spi_write_start: std_logic;
signal internal_spi_write_reg 	: std_logic_vector(23 downto 0);
signal internal_spi_write_done : std_logic;
----------------------------------------------------------
--data pipelining and management. At moment, one array per ADC (designated by 0 or 1)
signal rx_data_pipe0_a : std_logic_vector(63 downto 0); --pipelining
signal rx_data_pipe0_b : std_logic_vector(63 downto 0); --pipelining,  after bitshift alignment
signal rx_data_pipe0_ch0 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe0_ch1 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe0_ch2 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe0_ch3 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_aligned_ch0 : std_logic_vector(15 downto 0); --post adc sample alignment
signal rx_data_aligned_ch1 : std_logic_vector(15 downto 0); --post adc sample alignemnt
signal rx_data_aligned_ch2 : std_logic_vector(15 downto 0); --post adc sample alignment
signal rx_data_aligned_ch3 : std_logic_vector(15 downto 0); --post adc sample alignemnt
signal rx_data_pipe1_a : std_logic_vector(63 downto 0); --pipelining
signal rx_data_pipe1_b : std_logic_vector(63 downto 0); --pipelining, after bitshift alignment
signal rx_data_pipe1_ch4 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe1_ch5 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe1_ch6 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_pipe1_ch7 : std_logic_vector(63 downto 0); --puts bytes in right sample order, per-channel
signal rx_data_aligned_ch4 : std_logic_vector(15 downto 0); --post adc sample alignment
signal rx_data_aligned_ch5 : std_logic_vector(15 downto 0); --post adc sample alignemnt
signal rx_data_aligned_ch6 : std_logic_vector(15 downto 0); --post adc sample alignment
signal rx_data_aligned_ch7 : std_logic_vector(15 downto 0); --post adc sample alignemnt

signal internal_data_0 : std_logic_vector(63 downto 0); --after pre-trig block, write-side RAM
signal internal_data_1 : std_logic_vector(63 downto 0); --after pre-trig block, write-side RAM

signal rx_data_shift_array_0_a	: std_logic_vector(127 downto 0); --bitshifting array
signal rx_data_shift_array_1_a	: std_logic_vector(127 downto 0); --bitshifting array

signal internal_ram_data0_out : std_logic_vector(63 downto 0); --data on read-side of RAM
signal internal_ram_data1_out : std_logic_vector(63 downto 0); --data on read-side of RAM
--//bitshift selection
signal internal_bitshift_val_0	: std_logic_vector(2 downto 0); 
signal internal_bitshift_val_1	: std_logic_vector(2 downto 0); 
--//sample-align control
signal internal_samplealign_val_0 : std_logic_vector(2 downto 0); --adc0 byteshift
signal internal_samplealign_val_1 : std_logic_vector(2 downto 0); --adc1 byteshift
--//pretrigger selection
signal internal_pretrig_val	: std_logic_vector(3 downto 0); 
--pattern indicates 'no good data from ADC'
constant rx_data_HOLD_VALUE : std_logic_vector(63 downto 0) := x"CECECECECECECECE"; 
signal internal_data_good : std_logic;
signal internal_ram_read_en : std_logic_vector(1 downto 0) := (others=>'0');
signal internal_ram_read_clk_reg	: std_logic_vector(4 downto 0) := (others=>'0');
signal internal_ram_read_adr : std_logic_vector(9 downto 0);
--signal internal_ram_write_adr : std_logic_vector(9 downto 0) := (others=>'0');
--signal internal_ram_write_en : std_logic := '0';

constant offset : integer := 64; -- array offset for bit-shift operation
constant sample_align_offset : integer := 16; --array offset for adc-to-adc sample alignment
--
component signal_sync is
port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
end component;
----------------------------------------------------------
begin
pd0_o <= registers_i(to_integer(unsigned(adc_pd_reg_adr)))(0); 
pd1_o <= registers_i(to_integer(unsigned(adc_pd_reg_adr)))(0); 
rstn0_o <= '1'; --keep reset pins de-asserted // use internal registers
rstn1_o <= '1';
--////////////////////////////////////////////////////////////////////////
--//assign spi bus based on LSB in adc_config_reg_adr_0
proc_assign_spi_bus : process(clk_i)
begin
	if rising_edge(clk_i) then 
		case registers_i(to_integer(unsigned(adc_config_reg_adr_0)))(0) is
			when '0' =>
				sclk0_o <= internal_sclk;
				sdat0_o <= internal_sdat;
				csn0_o  <= internal_csn;
			when '1' =>
				sclk1_o <= internal_sclk;
				sdat1_o <= internal_sdat;
				csn1_o  <= internal_csn;
			when others=>
				Null; 
		end case;
	end if;
end process;
--//write ADC registers via software
proc_write_config : process(rst_i, clk_i, internal_spi_write_done, reg_addr_i)
begin
	if rst_i = '1' then
		internal_spi_write_reg 		<= (others=>'0');
		internal_spi_write_start	<= '0';
		write_config_state <= idle;
		
	elsif rising_edge(clk_i) then
		--//register data to write
		internal_spi_write_reg <= registers_i(to_integer(unsigned(adc_config_reg_adr_1)));
		--//control spi_write block:
		case write_config_state is
			when idle=>
				internal_spi_write_start	<= '0';
				--//toggle ADC register-write once software register is written to from SBC
				if reg_addr_i = adc_config_reg_adr_1 then	
					write_config_state <= write_reg;
				else
					write_config_state <= idle;
				end if;
			when write_reg=>
				internal_spi_write_start	<= '1';
				if internal_spi_write_done = '1' then
					write_config_state <= idle;
				else
					write_config_state <= write_reg;
				end if;
		end case;
	end if;
end process;

xSIMPLE_SPI_WRITE : entity work.spi_write
port map(
	rst_i	=> rst_i,	
	clk_i	=> clk_i,		
	pdat_i => internal_spi_write_reg,
	write_i => internal_spi_write_start,	
	done_o	=> internal_spi_write_done,	
	sdata_o	=> internal_sdat,	
	sclk_o	=> internal_sclk,	
	le_o	 => internal_csn);		
--////////////////////////////////////////////////////////////////////////
--//MANAGE the Rx FIFO; which transfers the pdata between the ADC DCLK and the core clock of the FPGA
proc_manage_rx_fifo : process(rst_i, clk_data_i, rx_fifo_usedwrd_i, 
										internal_bitshift_val_0, internal_bitshift_val_1)
begin
	if rst_i = '1' then
		rx_fifo_rd_en_o <= '0';
		internal_data_good <='0';
		rx_data_pipe0_a <= (others=>'0');
		rx_data_pipe1_a <= (others=>'0');
		rx_data_pipe0_b <= (others=>'0');
		rx_data_pipe1_b <= (others=>'0');
		rx_data_shift_array_0_a <= (others=>'0');
		rx_data_shift_array_1_a <= (others=>'0');
		
	elsif rising_edge(clk_data_i) and rx_fifo_usedwrd_i > 4 then --//arbitraryish -- FIFO is 8 words deep

		rx_fifo_rd_en_o <= '1';
		internal_data_good <='1';
		-----------------------------------------------------------
		--//BITSHIFTING STEP: align ADC output data frames with FPGA receiver using test-pattern mode
		case internal_bitshift_val_0 is -- ADC 0
			when "000" =>
				for i in 0 to 7 loop
					rx_data_pipe0_b(8*i+7 downto 8*i) <= rx_data_shift_array_0_a(offset+8*i+7 downto offset + 8*i);
				end loop;
			when "001" =>
				for i in 0 to 7 loop
					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+6 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7);
				end loop;
			when "010" =>
				for i in 0 to 7 loop
					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+5 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+6);
				end loop;
			when "011" =>
				for i in 0 to 7 loop
					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+4 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+5);
				end loop;
			when "100" =>
				for i in 0 to 7 loop
 					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+3 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+4);
				end loop;
			when "101" =>
				for i in 0 to 7 loop
 					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+2 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+3);
				end loop;
			when "110" =>
				for i in 0 to 7 loop
 					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset+8*i+1 downto offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+2);
				end loop;
			when "111" =>
				for i in 0 to 7 loop
 					rx_data_pipe0_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_0_a(offset + 8*i) &
																		rx_data_shift_array_0_a(8*i+7 downto 8*i+1);
				end loop;			
			when others=>
				Null;
		end case;
		
		case internal_bitshift_val_1 is -- ADC 1
			when "000" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <= rx_data_shift_array_1_a(offset+8*i+7 downto offset + 8*i);
				end loop;
			when "001" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+6 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7);																
				end loop;
			when "010" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+5 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+6);	
				end loop;
			when "011" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+4 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+5);	
				end loop;
			when "100" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+3 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+4);
				end loop;
			when "101" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+2 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+3);
				end loop;
			when "110" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset+8*i+1 downto offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+2) ;
				end loop;
			when "111" =>
				for i in 0 to 7 loop
					rx_data_pipe1_b(8*i+7 downto 8*i) <=  	rx_data_shift_array_1_a(offset + 8*i) &
																		rx_data_shift_array_1_a(8*i+7 downto 8*i+1);
				end loop;			
			when others=>
				Null;
		end case;
		--end bit-shift alignment for both ADCs
		---------------------------------------------------------------------
		--//test, for bypassing bitshift stuff:
		--rx_data_pipe0_b <= rx_data_pipe0_a;
		--rx_data_pipe1_b <= rx_data_pipe1_a;
		---------------------------------------
		rx_data_shift_array_0_a <= rx_data_shift_array_0_a(63 downto 0) & rx_adc0_data_i; --rx_data_pipe0_a;
		rx_data_shift_array_1_a <= rx_data_shift_array_1_a(63 downto 0) & rx_adc1_data_i; --rx_data_pipe1_a;
		-----removed this pipelining stage 8/20
		--rx_data_pipe0_a <= rx_adc0_data_i; 
		--rx_data_pipe1_a <= rx_adc1_data_i;
		
	--//no-good data condition:
	elsif rising_edge(clk_data_i) then 
		rx_fifo_rd_en_o <= '0';
		internal_data_good <='0';
		rx_data_shift_array_0_a <= rx_data_shift_array_0_a;
		rx_data_shift_array_1_a <= rx_data_shift_array_1_a;
		rx_data_pipe0_b <= rx_data_pipe0_a;
		rx_data_pipe1_b <= rx_data_pipe1_a;
		rx_data_pipe0_a <= rx_data_HOLD_VALUE;
		rx_data_pipe1_a <= rx_data_HOLD_VALUE;
	end if;
end process;
--////////////////////////////////////////////////////////////////////////
----re-arrange data into per-channel vectors. Assuming 4-ch board operation:
--rx_data_pipe0_ch0(31 downto 0) <= 	rx_data_pipe0_b(7 downto 0)   & rx_data_pipe0_b(15 downto 8) &
--												rx_data_pipe0_b(23 downto 16) & rx_data_pipe0_b(31 downto 24);
--rx_data_pipe0_ch1(31 downto 0) <= 	rx_data_pipe0_b(39 downto 32) & rx_data_pipe0_b(47 downto 40) &
--												rx_data_pipe0_b(55 downto 48) & rx_data_pipe0_b(63 downto 56);
--rx_data_pipe1_ch2(31 downto 0) <= 	rx_data_pipe1_b(7 downto 0)   & rx_data_pipe1_b(15 downto 8) &
--												rx_data_pipe1_b(23 downto 16) & rx_data_pipe1_b(31 downto 24);
--rx_data_pipe1_ch3(31 downto 0) <= 	rx_data_pipe1_b(39 downto 32) & rx_data_pipe1_b(47 downto 40) &
--												rx_data_pipe1_b(55 downto 48) & rx_data_pipe1_b(63 downto 56);

--re-arrange data into per-channel vectors. Assuming 8-ch board operation. Should probably array all of this for compactness											
rx_data_pipe0_ch0(15 downto 0) <= 	rx_data_pipe0_b(7 downto 0)   & rx_data_pipe0_b(15 downto 8);
rx_data_pipe0_ch1(15 downto 0) <= 	rx_data_pipe0_b(23 downto 16) & rx_data_pipe0_b(31 downto 24);
rx_data_pipe0_ch2(15 downto 0) <= 	rx_data_pipe0_b(39 downto 32) & rx_data_pipe0_b(47 downto 40);
rx_data_pipe0_ch3(15 downto 0) <= 	rx_data_pipe0_b(55 downto 48) & rx_data_pipe0_b(63 downto 56);
rx_data_pipe1_ch4(15 downto 0) <= 	rx_data_pipe1_b(7 downto 0)   & rx_data_pipe1_b(15 downto 8);
rx_data_pipe1_ch5(15 downto 0) <= 	rx_data_pipe1_b(23 downto 16) & rx_data_pipe1_b(31 downto 24);
rx_data_pipe1_ch6(15 downto 0) <= 	rx_data_pipe1_b(39 downto 32) & rx_data_pipe1_b(47 downto 40);
rx_data_pipe1_ch7(15 downto 0) <= 	rx_data_pipe1_b(55 downto 48) & rx_data_pipe1_b(63 downto 56);
												
--process to time-align datastreams between ADCs. SW controlled, using on-board pulser	fanout											
proc_sample_shift : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		--fill the arrays, again should compactify this code
		rx_data_pipe0_ch0(63 downto 48) <= rx_data_pipe0_ch0(47 downto 32);
		rx_data_pipe0_ch0(47 downto 32) <= rx_data_pipe0_ch0(31 downto 16);
		rx_data_pipe0_ch0(31 downto 16) <= rx_data_pipe0_ch0(15 downto 0);
		rx_data_pipe0_ch1(63 downto 48) <= rx_data_pipe0_ch1(47 downto 32);
		rx_data_pipe0_ch1(47 downto 32) <= rx_data_pipe0_ch1(31 downto 16);
		rx_data_pipe0_ch1(31 downto 16) <= rx_data_pipe0_ch1(15 downto 0);
		rx_data_pipe0_ch2(63 downto 48) <= rx_data_pipe0_ch2(47 downto 32);
		rx_data_pipe0_ch2(47 downto 32) <= rx_data_pipe0_ch2(31 downto 16);
		rx_data_pipe0_ch2(31 downto 16) <= rx_data_pipe0_ch2(15 downto 0);
		rx_data_pipe0_ch3(63 downto 48) <= rx_data_pipe0_ch3(47 downto 32);
		rx_data_pipe0_ch3(47 downto 32) <= rx_data_pipe0_ch3(31 downto 16);
		rx_data_pipe0_ch3(31 downto 16) <= rx_data_pipe0_ch3(15 downto 0);
		
		rx_data_pipe1_ch4(63 downto 48) <= rx_data_pipe1_ch4(47 downto 32);
		rx_data_pipe1_ch4(47 downto 32) <= rx_data_pipe1_ch4(31 downto 16);
		rx_data_pipe1_ch4(31 downto 16) <= rx_data_pipe1_ch4(15 downto 0);
		rx_data_pipe1_ch5(63 downto 48) <= rx_data_pipe1_ch5(47 downto 32);
		rx_data_pipe1_ch5(47 downto 32) <= rx_data_pipe1_ch5(31 downto 16);
		rx_data_pipe1_ch5(31 downto 16) <= rx_data_pipe1_ch5(15 downto 0);
		rx_data_pipe1_ch6(63 downto 48) <= rx_data_pipe1_ch6(47 downto 32);
		rx_data_pipe1_ch6(47 downto 32) <= rx_data_pipe1_ch6(31 downto 16);
		rx_data_pipe1_ch6(31 downto 16) <= rx_data_pipe1_ch6(15 downto 0);
		rx_data_pipe1_ch7(63 downto 48) <= rx_data_pipe1_ch7(47 downto 32);
		rx_data_pipe1_ch7(47 downto 32) <= rx_data_pipe1_ch7(31 downto 16);
		rx_data_pipe1_ch7(31 downto 16) <= rx_data_pipe1_ch7(15 downto 0);
		
		--rx_data_pipe0_ch1(63 downto 32) <= rx_data_pipe0_ch1(31 downto 0);
		--rx_data_pipe1_ch2(63 downto 32) <= rx_data_pipe1_ch2(31 downto 0);
		--rx_data_pipe1_ch3(63 downto 32) <= rx_data_pipe1_ch3(31 downto 0);
		
		case internal_samplealign_val_0 is --adjust ADC0 
			when "000" => --no adjustment
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 31-16 downto sample_align_offset);
			when "001" => --speed up by 1 sample
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 23-16 downto sample_align_offset-8);
			when "010" => --speed up by 2 samples
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 15-16 downto sample_align_offset-16);
			when "101" => --slow down by 1 sample
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 39-16 downto sample_align_offset+8);
			when "110" => --slow down by 2 samples
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 47-16 downto sample_align_offset+16);
			when others => --no adjustment
				rx_data_aligned_ch0 <= rx_data_pipe0_ch0(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch1 <= rx_data_pipe0_ch1(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch2 <= rx_data_pipe0_ch2(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch3 <= rx_data_pipe0_ch3(sample_align_offset + 31-16 downto sample_align_offset);
		end case;
		--//--
		case internal_samplealign_val_1 is --adjust ADC1
			when "000" => --no adjustment
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 31-16 downto sample_align_offset);
			when "001" => --speed up by 1 sample
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 23-16 downto sample_align_offset-8);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 23-16 downto sample_align_offset-8);
			when "010" => --speed up by 2 samples
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 15-16 downto sample_align_offset-16);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 15-16 downto sample_align_offset-16);
			when "101" => --slow down by 1 sample
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 39-16 downto sample_align_offset+8);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 39-16 downto sample_align_offset+8);
			when "110" => --slow down by 2 samples
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 47-16 downto sample_align_offset+16);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 47-16 downto sample_align_offset+16);
			when others => --no adjustment
				rx_data_aligned_ch4 <= rx_data_pipe1_ch4(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch5 <= rx_data_pipe1_ch5(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch6 <= rx_data_pipe1_ch6(sample_align_offset + 31-16 downto sample_align_offset);
				rx_data_aligned_ch7 <= rx_data_pipe1_ch7(sample_align_offset + 31-16 downto sample_align_offset);
		end case;
	end if;
end process;
--assign output data ports, goes to trigger
ch0_datastream_o <= x"0000" & rx_data_aligned_ch0;
ch1_datastream_o <= x"0000" & rx_data_aligned_ch1;
ch2_datastream_o <= x"0000" & rx_data_aligned_ch2;
ch3_datastream_o <= x"0000" & rx_data_aligned_ch3;
ch4_datastream_o <= x"0000" & rx_data_aligned_ch4;
ch5_datastream_o <= x"0000" & rx_data_aligned_ch5;
ch6_datastream_o <= x"0000" & rx_data_aligned_ch6;
ch7_datastream_o <= x"0000" & rx_data_aligned_ch7;
--////////////////////////////////////////////////////////////////////////
----MOVED RAM WRITING to data_manager.vhd 8.22/2021
--proc_simple_sw_trigger : process(rst_i, clk_data_i)
--begin
--	if rst_i = '1' then
--		internal_ram_write_adr <= (others=>'0');
--		internal_ram_write_en <= '0';
--	--//software trigger
--	elsif rising_edge(clk_data_i) and registers_i(to_integer(unsigned(software_trigger_reg_adr)))(0) = '1' then
--		internal_ram_write_adr <= (others=>'1');
--		internal_ram_write_en <= '0';
--	elsif rising_edge(clk_data_i) and internal_data_good = '1' then
--		internal_ram_write_adr <= internal_ram_write_adr + 1;
--		internal_ram_write_en <= '1';
--	end if;
--end process;
--////////////////////////////////////////////////////////////////////////
proc_assign_rd_en : process(registers_i(to_integer(unsigned(ram_select_reg_adr)))(7 downto 0))
begin
case (registers_i(to_integer(unsigned(ram_select_reg_adr)))(1 downto 0)) is
	when "00" =>
		internal_ram_read_en <= "00";
		adc_ram_data_o <= (others=>(others=>'0'));
	--//re-chunk output RAM data according to 2-channel/HMCAD operation 
	------> (0) is 1st ADC channel, (1) is 2nd ADC channel
	when "01" =>
		internal_ram_read_en <= "01";	
		adc_ram_data_o(0) <= internal_ram_data0_out(31 downto 0);
		adc_ram_data_o(1) <= internal_ram_data0_out(63 downto 32);
		--adc_ram_data_o(0) <= internal_ram_data0_out(7 downto 0)   & internal_ram_data0_out(15 downto 8) &
		--							internal_ram_data0_out(23 downto 16) & internal_ram_data0_out(31 downto 24);
		--adc_ram_data_o(1) <= internal_ram_data0_out(39 downto 32) & internal_ram_data0_out(47 downto 40) &
		--							internal_ram_data0_out(55 downto 48) & internal_ram_data0_out(63 downto 56);
		--adc_ram_data_o(0) <= internal_ram_data0_out(55 downto 48) & internal_ram_data0_out(39 downto 32) &
		--							internal_ram_data0_out(23 downto 16) & internal_ram_data0_out(7 downto 0);
		--adc_ram_data_o(1) <= internal_ram_data0_out(63 downto 56) & internal_ram_data0_out(47 downto 40) &
		--							internal_ram_data0_out(31 downto 24) & internal_ram_data0_out(15 downto 8);
	when "10" =>
		internal_ram_read_en <= "10";
		adc_ram_data_o(0) <= internal_ram_data1_out(31 downto 0);
		adc_ram_data_o(1) <= internal_ram_data1_out(63 downto 32);
		--adc_ram_data_o(0) <= internal_ram_data1_out(7 downto 0)   & internal_ram_data1_out(15 downto 8) &
		--							internal_ram_data1_out(23 downto 16) & internal_ram_data1_out(31 downto 24);
		--adc_ram_data_o(1) <= internal_ram_data1_out(39 downto 32) & internal_ram_data1_out(47 downto 40) &
		--							internal_ram_data1_out(55 downto 48) & internal_ram_data1_out(63 downto 56);
		--adc_ram_data_o(0) <= internal_ram_data1_out(55 downto 48) & internal_ram_data1_out(39 downto 32) &
		--							internal_ram_data1_out(23 downto 16) & internal_ram_data1_out(7 downto 0);
		--adc_ram_data_o(1) <= internal_ram_data1_out(63 downto 56) & internal_ram_data1_out(47 downto 40) &
		--							internal_ram_data1_out(31 downto 24) & internal_ram_data1_out(15 downto 8);
	when others=>
		internal_ram_read_en <= "00";
		adc_ram_data_o <= (others=>(others=>'0'));
end case;
end process;
--////////////////////////////////////////////////////////////////////////
--//RAM Read process definitions here
process(clk_i, rst_i, registers_i)
begin
	if rst_i = '1' then
		internal_ram_read_clk_reg <= (others=>'0');
	elsif rising_edge(clk_i) then
		--///////////////////
		--//update read address and pulse the read clk
		--------------------------------------------------
		--//delay the ram read clock by one clock cycle after the address is set
		internal_ram_read_clk_reg(4 downto 1) <= internal_ram_read_clk_reg(3 downto 0);
		if internal_ram_read_clk_reg(0) = '1' then
			internal_ram_read_adr <= registers_i(to_integer(unsigned(ram_read_adr_reg_adr)))(9 downto 0);
		end if;
		case reg_addr_i is
			when ram_read_adr_reg_adr =>
				internal_ram_read_clk_reg(0) <= '1';
			when others=>
				internal_ram_read_clk_reg(0) <= '0';
		end case;
	end if;
end process;
--////////////////////////////////////////////////////////////////////////
--PRETRIGGER
xPRETRIG_0 : entity work.pretrigger_window --ADC0
	port map(
		rst_i				=> rst_i,
		clk_i				=> clk_data_i,	
		pretrig_sel_i	=> internal_pretrig_val,	
		data_i			=> rx_data_aligned_ch3 & rx_data_aligned_ch2 & rx_data_aligned_ch1 & rx_data_aligned_ch0,	
		data_o			=> internal_data_0);	
xPRETRIG_1 : entity work.pretrigger_window --ADC1
	port map(
		rst_i				=> rst_i,
		clk_i				=> clk_data_i,	
		pretrig_sel_i	=> internal_pretrig_val,	
		data_i			=> rx_data_aligned_ch7 & rx_data_aligned_ch6 & rx_data_aligned_ch5 & rx_data_aligned_ch4,	
		data_o			=> internal_data_1);	
--////////////////////////////////////////////////////////////////////////
--One RAM block per ADC
xRAM0 : entity work.data_ram --ADC0
	port map(
		out_aclr	=> rst_i,
		data 		=> internal_data_0,
		wraddress=> ram_write_adr_i, --internal_ram_write_adr,
		wren		=> ram_write_en_i, --internal_ram_write_en,
		rdaddress=> registers_i(to_integer(unsigned(ram_read_adr_reg_adr)))(9 downto 0),
		rden		=> internal_ram_read_en(0),
		inclock	=> clk_data_i,
		outclock	=> internal_ram_read_clk_reg(2),
		q			=> internal_ram_data0_out);
xRAM1 : entity work.data_ram --ADC1
	port map(
		out_aclr	=> rst_i,
		data 		=> internal_data_1,
		wraddress=> ram_write_adr_i, --internal_ram_write_adr,
		wren		=> ram_write_en_i, --internal_ram_write_en,
		rdaddress=> registers_i(to_integer(unsigned(ram_read_adr_reg_adr)))(9 downto 0),
		rden		=> internal_ram_read_en(1),
		inclock	=> clk_data_i,
		outclock	=> internal_ram_read_clk_reg(2),
		q			=> internal_ram_data1_out);
--////////////////////////////////////////////////////////////////////////
--//sync some software commands to the data clock
BITSHIFT_CMD_ADC_0 : for i in 0 to 2 generate
	xBITSHIFTSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(bitshift_reg_adr)))(i), --bitshift from software
		SignalOut_clkB	=> internal_bitshift_val_0(i));
end generate;
BITSHIFT_CMD_ADC_1 : for i in 0 to 2 generate
	xBITSHIFTSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(bitshift_reg_adr)))(i+8), --bitshift from software
		SignalOut_clkB	=> internal_bitshift_val_1(i));
end generate;
SAMPLESHIFT_CMD_ADC_1 : for i in 0 to 2 generate
	xBITSHIFTSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(adc1_sample_shift_adr)))(i), --bitshift from software
		SignalOut_clkB	=> internal_samplealign_val_1(i));
end generate;
SAMPLESHIFT_CMD_ADC_0 : for i in 0 to 2 generate
	xBITSHIFTSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(adc0_sample_shift_adr)))(i), --bitshift from software
		SignalOut_clkB	=> internal_samplealign_val_0(i));
end generate;
PRETRIG_CMD : for i in 0 to 3 generate
	xPRETRIGSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(pretrig_reg_adr)))(i), --pretrig from software
		SignalOut_clkB	=> internal_pretrig_val(i));
end generate;
end rtl;