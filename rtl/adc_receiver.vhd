---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      greenland low-threshold system
-- FILE:         adc_receiver.vhd
-- AUTHOR:       
-- EMAIL         
-- DATE:         04/2020, onwards
--
-- DESCRIPTION:  adc data capture / clock-domain transfer / re-packing
--		
---------------------------------------------------------------------------------
library IEEE; 
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity adc_receiver is
Generic(
	adc_data_parallel_width : integer := 64;
	adc_dat_valid_reg_adr   : std_logic_vector(7 downto 0):= x"3A"); --//ADC data valid set register
Port(
	adc_dA_i		: in 	std_logic_vector(3 downto 0);
	adc_dB_i		: in 	std_logic_vector(3 downto 0);
	adc_fclk_i	: in 	std_logic; --data frame clock
	adc_lclk_i	: in 	std_logic; --data ddr clock
	
	registers_i	: in	register_array_type;

	rst_i			: in 	std_logic;
	clk_i			: in 	std_logic;
	clk_reg_i	: in	std_logic;
	
	rx_fifo_rdusedw_o : out std_logic_vector(2 downto 0);
	rx_fifo_rd_i		: in std_logic; --read request
	rx_adc_data_o		: out std_logic_vector(adc_data_parallel_width-1 downto 0);
	serdes_clk_o		:	out std_logic);
end adc_receiver;

architecture rtl of adc_receiver is

--signal data_in_ch0 : std_logic_vector(3 downto 0);
--signal data_in_ch1 : std_logic_vector(3 downto 0);
signal internal_adc_serial_data : std_logic_vector(7 downto 0) := (others=>'0');
signal internal_adc_parallel_data : std_logic_vector(adc_data_parallel_width-1 downto 0) := (others=>'0');
signal internal_serdes_outclk	: std_logic;

signal internal_fifo_wr_en : std_logic;
signal internal_rx_dat_valid : std_logic_vector(2 downto 0);-- := (others=>'0');
signal internal_rx_dat_valid_flag : std_logic := '0';

component rxserdes
port (rx_in : in std_logic_vector(7 downto 0);
		rx_inclock	: in std_logic;
		rx_out : out std_logic_vector(adc_data_parallel_width-1 downto 0);
		rx_outclock	: out std_logic);
end component;
component signal_sync is
port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
end component;
begin
-------------------------------------------------
----hmcad1511 2-channel operation:
--data_in_ch0(1 downto 0) <= adc_dA_i(1 downto 0)
--data_in_ch0(3 downto 2) <= adc_dB_i(1 downto 0)
--
--data_in_ch1(1 downto 0) <= adc_dA_i(3 downto 2)
--data_in_ch1(3 downto 2) <= adc_dB_i(3 downto 2)
-------------------------------------------------
--
internal_adc_serial_data <= 	adc_dB_i(3) & adc_dA_i(3) & adc_dB_i(2) & adc_dA_i(2) &
										adc_dB_i(1) & adc_dA_i(1) & adc_dB_i(0) & adc_dA_i(0);
										
serdes_clk_o <= internal_serdes_outclk;

--//factor of 8 deserialization 
xRXSERDES: rxserdes
port map(
	rx_in => internal_adc_serial_data,
	rx_inclock => adc_lclk_i, --//LVDS_bit_clock (472MHz, DDR)
	rx_out => internal_adc_parallel_data,
	rx_outclock => internal_serdes_outclk); --//LVDS_bit_clock/4 -- 118MHz

--//FIFO, 8-words deep 8/19
xRXFIFO : entity work.rx_fifo(syn)
port map(
	aclr			=> rst_i or (not internal_rx_dat_valid(1)),
	data			=> internal_adc_parallel_data,
	rdclk			=> clk_i,
	rdreq			=> rx_fifo_rd_i,
	wrclk			=> internal_serdes_outclk,
	wrreq			=> internal_fifo_wr_en,
	q				=> rx_adc_data_o,
	rdusedw 		=> rx_fifo_rdusedw_o,	
	rdempty => open, wrfull => open, wrusedw => open);
	
--// write ADC data to fifo, needs commanding from sw to begin
proc_write_fifo : process(internal_serdes_outclk, internal_rx_dat_valid)
begin	
	if internal_rx_dat_valid(0) = '0'  then
		internal_fifo_wr_en	<= '0';
	elsif rising_edge(internal_serdes_outclk) and internal_rx_dat_valid(internal_rx_dat_valid'length-1) = '1' then
		internal_fifo_wr_en	<= '1';
	end if;		
end process;
--// establish a data-valid flag 
proc_data_valid : process(internal_serdes_outclk, rst_i)
begin
	if rst_i = '1' then	
		internal_rx_dat_valid(internal_rx_dat_valid'length-1 downto 0) <= (others =>'0');
	elsif rising_edge(internal_serdes_outclk) then
		internal_rx_dat_valid <= internal_rx_dat_valid(internal_rx_dat_valid'length-2 downto 0) & internal_rx_dat_valid_flag;
	end if;
end process;
---------------------------------------------------------	
xDATVALIDSYNC : signal_sync
port map(
		clkA				=> clk_reg_i,
		clkB				=> internal_serdes_outclk,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(adc_dat_valid_reg_adr)))(8), --data valid from software
		SignalOut_clkB	=> internal_rx_dat_valid_flag);	
---------------------------------------------------------
end rtl;