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
		address_reg_sw_trig :  std_logic_vector(7 downto 0):= x"40";
		address_reg_clear_buffer_full : std_logic_Vector(7 downto 0):= x"4D";
		address_reg_reset_evt_counters :  std_logic_vector(7 downto 0):= x"7E");

port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 10MHz
		clk_data_i	:	in		std_logic; --data clock 118MHz
		registers_i	:	in		register_array_type;
		
		coinc_trig_i:  in		std_logic;
		phase_trig_i:	in		std_logic;
		ext_trig_i	:  in		std_logic;
		pps_i			:	in		std_logic;
		
		status_reg_o : out 	std_logic_vector(23 downto 0);
		ram_write_o			:	out	std_logic; -- ram sits in ADC controller for now, control signal
		ram_write_adr_o 	:  buffer   std_logic_vector(9 downto 0);
		evt_meta_o			:  out	event_metadata_type		);
end data_manager;

architecture rtl of data_manager is

signal internal_sw_trig_reg : std_logic_vector(1 downto 0); 
signal internal_Sw_trig : std_logic := '0';          -- generate sw trigger from registers, one clk_data_i cycle
signal internal_ext_trig_reg : std_logic_vector(1 downto 0); 
signal internal_ext_trig : std_logic := '0';          -- generate ext trigger from board
signal internal_pps_trig_reg : std_logic_vector(1 downto 0); 
signal internal_pps_trig : std_logic := '0';          -- generate ext trigger from board
signal internal_trig_to_save_data : std_logic:= '0'; -- signal to tell ram to save data

--metadata stuff
signal internal_trigger_type : std_logic_vector(3 downto 0) := "0000";
signal internal_multiple_trigger_flag : std_logic := '0'; --flags if a second trigger caught while writing data to buffer
signal internal_event_timestamp_counter : std_logic_vector(47 downto 0) := (others=>'0');
signal internal_event_counter : std_logic_vector(23 downto 0) := (others=>'0');
signal internal_trigger_counter : std_logic_vector(23 downto 0) := (others=>'0'); --all trigger types combined
signal internal_pps_counter : std_logic_vector(23 downto 0) := (others=>'0'); 
signal internal_event_pps_counter : std_logic_vector(23 downto 0) := (others=>'0'); 
signal internal_running_timestamp : std_logic_vector(47 downto 0);

signal internal_write_busy : std_logic_vector(1 downto 0) := "00";
signal internal_buffer_full : std_logic; --still only a single buffer 
constant maximum_ram_address : std_logic_vector(9 downto 0) := (others=>'1');

signal internal_metadata_array : event_metadata_type;

type data_save_state_type is (idle, write_ram, buffer_full);
signal data_save_state : data_save_state_type;
--
------------------------------------
begin
------------------------------------
--process/generate some triggers 
process(clk_data_i)
begin
	if rst_i = '1' then
		internal_sw_trig_reg <= (others=>'0');
		internal_ext_trig_reg <= (others=>'0');
		internal_pps_trig_reg <= (others=>'0');
	elsif rising_edge(clk_data_i) then
		internal_sw_trig_reg <= internal_sw_trig_reg(0) & (registers_i(to_integer(unsigned(address_reg_sw_trig)))(0));
		internal_ext_trig_reg <= internal_ext_trig_reg(0) & ext_trig_i; --rising edge condition
		internal_pps_trig_reg <= internal_pps_trig_reg(0) & pps_i; --rising edge condition
	end if;
end process;
proc_make_trig_pulse : process(clk_data_i, internal_sw_trig_reg, internal_ext_trig_reg,
		                         coinc_trig_i, phase_trig_i)
begin
	if rising_edge(clk_data_i) then
		if internal_sw_trig_reg = "01" then	
			internal_Sw_trig <= '1'; --pulse for one clk_data_i cycle
		else
			internal_Sw_trig <= '0';
		end if;
		if internal_ext_trig_reg = "01" then	
			internal_ext_trig <= '1'; --pulse for one clk_data_i cycle
		else
			internal_ext_trig <= '0';
		end if;
		if internal_pps_trig_reg = "01" then	
			internal_pps_trig <= '1'; --pulse for one clk_data_i cycle
		else
			internal_pps_trig <= '0';
		end if;
		------------------------------
		if internal_Sw_trig = '1' then
			internal_trig_to_save_data  <= '1';
			internal_trigger_type <= "0001";
		elsif internal_ext_trig = '1' then
			internal_trig_to_save_data  <= '1';
			internal_trigger_type <= "0010";
		elsif coinc_trig_i = '1' then
			internal_trig_to_save_data  <= '1';
			internal_trigger_type <= "0011";
		elsif phase_trig_i = '1' then
			internal_trig_to_save_data  <= '1';
			internal_trigger_type <= "0100";
		elsif internal_pps_trig = '1' then
			internal_trig_to_save_data  <= '1';
			internal_trigger_type <= "0101";
		else
			internal_trig_to_save_data  <= '0';
			internal_trigger_type <= internal_trigger_type; --hold last value
		end if;
	end if;
end process;
------------------------------------
--timestamping / counters:
proc_meta_counters : process(clk_data_i, internal_trig_to_save_data, internal_write_busy)
begin
	if rst_i = '1' then
		internal_event_timestamp_counter <= (others=>'0');
		internal_running_timestamp <= (others=>'0');
		internal_event_counter <= (others=>'0');
		internal_trigger_counter <= (others=>'0');
		internal_pps_counter <= (others=>'0');
	--software reset condition:
	elsif rising_edge(clk_data_i) and registers_i(to_integer(unsigned(address_reg_reset_evt_counters )))(0) = '1' then
		internal_event_timestamp_counter <= (others=>'0');
		internal_running_timestamp <= (others=>'0');
		internal_event_counter <= (others=>'0');
		internal_trigger_counter <= (others=>'0');
		internal_pps_counter <= (others=>'0');
	--incrementationing
	elsif rising_edge(clk_data_i) then
		internal_running_timestamp <= internal_running_timestamp + 1;
		
		if internal_trig_to_save_data = '1' then
			internal_trigger_counter <= internal_trigger_counter + 1;
			internal_event_timestamp_counter <= internal_running_timestamp;
			internal_event_pps_counter <= internal_pps_counter;
		end if;
		
		if internal_pps_trig = '1' then
			internal_pps_counter <= internal_pps_counter + 1;
		end if;
		
		--only increment event counter if event is saved. event_counter < = trig_counter
		if internal_write_busy = "01" then
			internal_event_counter <= internal_event_counter + 1;
		end if;
		
	end if;
end process;	
------------------------------------
--control data RAM and latch metadata
proc_record_event : process(rst_i, clk_data_i, internal_trig_to_save_data)
begin
	if rst_i = '1' then
		ram_write_adr_o <= (others=>'1');
		ram_write_o <= '0';
		internal_metadata_array <= (others=>(others=>'0'));
		internal_write_busy <= "00";
		internal_buffer_full <= '0';
		data_save_state <= idle;

	elsif rising_edge(clk_data_i) then
		internal_write_busy(1) <= internal_write_busy(0);

		case data_save_state is
			when idle=>
				ram_write_o <= '0';
				ram_write_adr_o <= (others=>'0');
				internal_write_busy(0) <= '0';
				internal_buffer_full <= '0';
				if internal_trig_to_save_data = '1' then
					data_save_state <= write_ram;
				else
					data_save_state <= idle;
				end if;
			
			when write_ram=>
				internal_write_busy(0) <= '1';
				internal_buffer_full <= '0';
				if ram_write_adr_o  = maximum_ram_address then --TODO make configurable
					ram_write_o <= '0';
					ram_write_adr_o <= ram_write_adr_o;
					data_save_state <= buffer_full;
				else
					ram_write_o <= '1';
					ram_write_adr_o <= ram_write_adr_o + 1;
					data_save_state <= write_ram;
				end if;
				
			when buffer_full=>
				internal_write_busy(0) <= '0';
				internal_buffer_full <= '1';
				ram_write_o <= '0';
				ram_write_adr_o <= (others=>'0');
				if registers_i(to_integer(unsigned(address_reg_clear_buffer_full )))(0) = '1' then
					data_save_state <= idle;
				else
					data_save_state <= buffer_full;
				end if;
		end case;
		
		--latch event metadata using write busy signaling
		if internal_write_busy = "01" then
			internal_metadata_array(0) <= internal_event_counter + 1; -- +1 to maintain same value for event and trig counter
			internal_metadata_array(1) <= internal_trigger_counter;
			internal_metadata_array(2) <= internal_pps_counter;
			internal_metadata_array(3) <= internal_event_timestamp_counter(23 downto 0);
			internal_metadata_array(4) <= internal_event_timestamp_counter(47 downto 24);
			internal_metadata_array(5) <= x"0" & "000" & pps_i & x"00" & x"0" & internal_trigger_type;
		end if;
	end if;
end process;	
------------------------------------
proc_clk_meta : process(clk_i)
begin
	if rising_edge(clk_i) then
		evt_meta_o <= internal_metadata_array;
		status_reg_o <= x"00" & "0000000" & internal_write_busy(0) & "0000000" & internal_buffer_full;
	end if;
end process;
------------------------------------
end rtl;