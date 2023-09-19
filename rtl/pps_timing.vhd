---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         pps_timing.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         9/2022
--
-- DESCRIPTION:  some timing crap
--
--         
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity pps_timing is
generic(
		address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E"
		);

port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 
		clk_10MHz_i	:	in		std_logic; --10MHz system
		clk_data_i	:	in		std_logic; --data clock 118MHz
		registers_i	:	in		register_array_type;
		pps_i			:  in		std_logic;
		pps_o			:	out	std_logic; -- delayed pps output
		pps_fast_flag_o : out	std_logic;  --for board synchronization
		pps_cycle_counter_o : out	std_logic_vector(47 downto 0)
		
		);
end pps_timing;

architecture rtl of pps_timing is

type pps_delay_state_type is (idle, delay, pulse);
signal pps_delay_state : pps_delay_state_type;
signal internal_pps_reg : std_logic_vector(1 downto 0); 
signal internal_pps_delay_counter : std_logic_vector(23 downto 0) := (others=>'0'); 

signal internal_pps_fast_reg : std_logic_vector(1 downto 0); 
signal internal_pps_fast_counter : std_logic_vector(47 downto 0) := (others=>'0'); --for counting pps data clk cycles
signal internal_pps_fast_counter_latched : std_logic_vector(47 downto 0) := (others=>'0'); --for counting pps data clk cycles
signal internal_pps_fast_counter_start : std_logic := '0';

begin
------------------------------------------------
--delayed pps trigger-out option, do this on the 10MHz system clock
----
process(clk_10MHz_i, rst_i, pps_i)
begin
	if rst_i = '1' then
		pps_o <= '0';
		internal_pps_reg <= (others=>'0');
		internal_pps_delay_counter <= (others=>'0');
		pps_delay_state <= idle;
	elsif rising_edge(clk_10MHz_i) then
		internal_pps_reg <= internal_pps_reg(0) & pps_i; --rising edge condition

		case pps_delay_state is
			--idle
			when idle=>
				pps_o <= '0';
				internal_pps_delay_counter <= (others=>'0');
				if internal_pps_reg = "01" then --pps_i rising-edge caught
					pps_delay_state <= delay;
				else
					pps_delay_state <= idle;
				end if;
			--delay
			when delay=>
				pps_o <= '0';
				internal_pps_delay_counter <= internal_pps_delay_counter + 1;
				if internal_pps_delay_counter >= registers_i(to_integer(unsigned(address_reg_pps_delay)))(23 downto 0) then
					pps_delay_state <= pulse;
				else
					pps_delay_state <= delay;
				end if;
			--pulse
			when pulse=>
				pps_o <= '1'; --pulse for one clk_i cycle
				internal_pps_delay_counter <= (others=>'0');
				pps_delay_state <= idle;
		end case;
	end if;
end process;
------------------------------------------------
--pps cycle counter, do this on a faster clock
process(clk_data_i, rst_i, pps_i) 
begin
	if rst_i = '1' then
		internal_pps_fast_reg <= (others=>'0');
		internal_pps_fast_counter <= (others=>'0');
		internal_pps_fast_counter_start <= '0';
		internal_pps_fast_counter_latched <= (others=>'0');
		pps_fast_flag_o <= '0';
		
	elsif rising_edge(clk_data_i) then
		internal_pps_fast_reg <= internal_pps_fast_reg(0) & pps_i; --rising edge condition
		--run counter every-other pps cycle using start signal
		if internal_pps_fast_reg = "01" then --pps_i rising-edge caught
			internal_pps_fast_counter_start <= not internal_pps_fast_counter_start;
			pps_fast_flag_o <= '1';
		else
			internal_pps_fast_counter_start <= internal_pps_fast_counter_start;
			pps_fast_flag_o <= '0';
		end if;
		--dumb way of latching and resetting counter
		if internal_pps_fast_counter_start = '0' and internal_pps_fast_reg = "10" then
			internal_pps_fast_counter_latched <= internal_pps_fast_counter;
			internal_pps_fast_counter <= internal_pps_fast_counter;
		elsif internal_pps_fast_counter_start = '0' and internal_pps_fast_reg = "00" then
			internal_pps_fast_counter_latched <= internal_pps_fast_counter_latched;
			internal_pps_fast_counter <= (others=>'0');
		elsif internal_pps_fast_counter_start = '1' then
			internal_pps_fast_counter_latched <= internal_pps_fast_counter_latched;
			internal_pps_fast_counter <= internal_pps_fast_counter + 1;
		else
			internal_pps_fast_counter_latched <= internal_pps_fast_counter_latched;
			internal_pps_fast_counter <= internal_pps_fast_counter;
		end if;
		
	end if;
end process;
--put the latched counter value on the register clock for the scaler read
process(clk_i)
begin
	if rising_edge(clk_i) then
		pps_cycle_counter_o <= internal_pps_fast_counter_latched;
	end if;
end process;

end rtl;