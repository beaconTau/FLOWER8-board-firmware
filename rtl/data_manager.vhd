---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         data_manager.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         8/2021
--
-- DESCRIPTION:  simple data and meta-data manager
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity data_manager is
generic(
		address_reg_sw_trig :  std_logic_vector(7 downto 0):= x"40");
port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 
		clk_data_i	:	in		std_logic; --data clock
		registers_i	:	in		register_array_type;
		
		coinc_trig_i:  in		std_logic;
		phase_trig_i:	in		std_logic;
		ext_trig_i	:  in		std_logic;
		pps_in_i		:	in		std_logic;
		
		ram_write_o			:	out	std_logic; -- ram sits in ADC controller for now, control signal
		ram_write_adr_o 	:  out   std_logic_vector(9 downto 0);
		evt_meta_o			:  out	event_metadata_type		);
end data_manager;

architecture rtl of data_manager is

signal internal_sw_trig_reg : std_logic_vector(1 downto 0); 
signal internal_Sw_trig : std_logic := '0';          -- generate sw trigger from registers, one clk_data_i cycle
signal internal_trig_to_save_data : std_logic:= '0'; -- signal to tell ram to save data
signal internal_write_busy : std_logic;

--metadata stuff
signal internal_trigger_type : std_logic_vector(3 downto 0) := '0000';
signal internal_multiple_trigger_flag : std_logic := '0'; --flags if a second trigger caught while writing data to buffer
signal internal_event_timestamp_counter : std_logic_vector(47 downto 0) := (others=>'0');
signal internal_event_counter : std_logic_vector(23 downto 0) := (others=>'0');
signal internal_trigger_counter : std_logic_vector(23 downto 0) := (others=>'0'); --all trigger types combined

signal internal_meta_counter_reset : std_logic := '0'; --reset metadata counters from sw
signal internal_running_timestamp : std_logic_vector(47 downto 0);
begin
------------------------------------
--generate sw trigger
process(clk_i)
begin
	if rst_i then
		internal_sw_trig_reg <= (others=>'0');
	elsif rising_edge(clk_i) then
		internal_sw_trig_reg <= internal_sw_trig_reg(0) & (registers_i(to_integer(unsigned(software_trigger_reg_adr)))(0);
	end if;
end process;

process(clk_data_i, internal_sw_trig_reg)
begin
	if rising_edge(clk_data_i) then
		if internal_sw_trig_reg = "01" then	
			internal_Sw_trig <= '1'; --pulse for one clk_data_i cycle
		else
			internal_Sw_trig <= '0';
		end if;
end process;
------------------------------------


end rtl;