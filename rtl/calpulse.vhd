---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      phased-array trigger board
-- FILE:         electronics_calpulse.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         5/2017...
--
-- DESCRIPTION:  Pulse and enable for plug-in-line cal pulse board, which
--               allows user to line up ADC timestreams
--					  --//managed by register 42
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use work.defs.all;

entity calpulse is
	generic(
		address_reg_cal_pulse: std_logic_vector(7 downto 0) := x"2A";
		ENABLE_CALIBRATION_PULSE : std_logic := '1');
	port(
		rst_i			:	in		std_logic;  --//async reset
		clk_reg_i	:	in		std_logic;	--//slow register clock
		clk_i			: 	in		std_logic;  --//fast clock to run DDR output		
		reg_i			: 	in		register_array_type;		--//system registers	
		pps_fast_sync_i : in std_logic;  --// fast sync from pps timing block
		pulse_o		:	out	std_logic;  --//fast pulse to board SMA
		rf_switch_o :	out	std_logic); --//pick RF switch input
end calpulse;

architecture rtl of calpulse is
--//with input clock, clk_i
-----//Repetition Period  is d_length / clk_i ~> 1 microsec @ clk_i = 118MHz
constant d_length : integer := 1024;
signal data_h : std_logic_vector(d_length-1 downto 0) := (others=>'0');
signal data_l : std_logic_vector(d_length-1 downto 0) := (others=>'0');
signal index  : std_logic_vector(7 downto 0) := (others=>'0'); --//matches d_length, number of bits 
signal data_h_current_value : std_logic_vector(0 downto 0);
signal data_l_current_value : std_logic_vector(0 downto 0);
signal data_out_current_value : std_logic_vector(0 downto 0);
signal internal_pulse_sync	: std_logic;
signal internal_pulse_en	: std_logic;

type sync_pulse_state_type is (get_sync, make_pulse);
signal sync_pulse_state : sync_pulse_state_type;

--------------
component signal_sync is
port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
end component;

--//
begin
data_h(0) <= '1'; --//single hi bit for pulse
proc_freq_sel : process(reg_i(to_integer(unsigned(address_reg_cal_pulse)))(8))
begin
case reg_i(42)(8) is
	when '0' =>
		data_h(128) <= '1';
		data_h(256) <= '1';
		data_h(384) <= '1';
		data_h(512) <= '1';
		data_h(640) <= '1';
		data_h(768) <= '1';
		data_h(896) <= '1';
	when '1' => --factor of 8 lower rep rate
		data_h(128) <= '0';
		data_h(256) <= '0';
		data_h(384) <= '0';
		data_h(512) <= '0';
		data_h(640) <= '0';
		data_h(768) <= '0';
		data_h(896) <= '0';
end case;
end process;
----///////////
rf_switch_o <= not (reg_i(to_integer(unsigned(address_reg_cal_pulse)))(1)); --//set rf switch input selection [reg(42)(1) = 1 --> switch to pulse ;; reg(42)(1) = 0 --> switch to signal chain] 
--/////////////
pulse_o <= data_out_current_value(0);
--/////////////
proc_cycle_data : process(rst_i, reg_i, clk_i, pps_fast_sync_i, internal_pulse_sync)
begin
	if rst_i = '1' or reg_i(to_integer(unsigned(address_reg_cal_pulse)))(0) = '0' or ENABLE_CALIBRATION_PULSE = '0' then
		data_h_current_value(0) <= '0';
		data_l_current_value(0) <= '0';
		index <= (others=>'0');
		sync_pulse_state <= get_sync;
	--wait for pps sync to start pulser
	elsif rising_edge(clk_i) and internal_pulse_sync = '1' then
		case sync_pulse_state is
			when get_sync =>
				data_h_current_value(0) <= '0';
				data_l_current_value(0) <= '0';
				index <= (others=>'0');
				if pps_fast_sync_i = '1' then
					sync_pulse_state <= make_pulse;
				else
					sync_pulse_state <= get_sync;
				end if;
				
			when make_pulse =>
				data_h_current_value(0) <= data_h(to_integer(unsigned(index)));
				data_l_current_value(0) <= data_l(to_integer(unsigned(index)));
				index <= index + 1;
				sync_pulse_state <= make_pulse; --stuck here until exit cal pulser mode!
				
			when others =>
				sync_pulse_state <= get_sync;
		end case;
	--just start pulse train			
	elsif rising_edge(clk_i) and internal_pulse_sync = '0' then
		data_h_current_value(0) <= data_h(to_integer(unsigned(index)));
		data_l_current_value(0) <= data_l(to_integer(unsigned(index)));
		index <= index + 1;
		sync_pulse_state <= get_sync;
	end if;
end process;

xSYNC_SYNC : signal_sync
port map(
	clkA				=> clk_reg_i,
	clkB				=> clk_i,
	SignalIn_clkA	=> reg_i(to_integer(unsigned(address_reg_cal_pulse)))(16), 
	SignalOut_clkB	=> internal_pulse_sync);
xEN_SYNC : signal_sync
port map(
	clkA				=> clk_reg_i,
	clkB				=> clk_i,
	SignalIn_clkA	=> reg_i(to_integer(unsigned(address_reg_cal_pulse)))(0), 
	SignalOut_clkB	=> internal_pulse_en);
	
	
--/////////////////////////////////////////
--//pulse generated using DDR output buffer
xDDRPULSEGENERATOR : entity work.DDRout
port map(
	aclr			=>	rst_i or (not ENABLE_CALIBRATION_PULSE),
	datain_h		=> data_h_current_value,
	datain_l		=> data_l_current_value,
	outclock		=> clk_i,
	outclocken	=> reg_i(to_integer(unsigned(address_reg_cal_pulse)))(0) and ENABLE_CALIBRATION_PULSE,
	dataout		=>	data_out_current_value);
end rtl;
