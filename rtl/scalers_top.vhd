---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      phased-array trigger board
-- FILE:         scalers_top.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         7/2017
--
-- DESCRIPTION:  manage board scalers and readout of scalers 
--               
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity scalers_top is
	generic(
		scaler_width   : integer := 12);
	port(
		rst_i				:		in		std_logic;
		clk_i				:		in 	std_logic;
		gate_i			:		in		std_logic;
		reg_i				:		in		register_array_type;
		coinc_trig_bits_i : in std_logic_vector(11 downto 0);
		--trigger_i		:		in		std_logic;

		--beam_trig_i		:		in		std_logic_vector(define_num_beams-1 downto 0);
		pps_timestamp_i		  :		in		std_logic_vector(47 downto 0);
		pps_timestamp_latched_o :		out	std_logic_vector(47 downto 0);
		
		scaler_to_read_o  :   out	std_logic_vector(23 downto 0));
end scalers_top;

architecture rtl of scalers_top is

constant num_scalers : integer := 64;
type scaler_array_type is array(num_scalers-1 downto 0) of std_logic_vector(scaler_width-1 downto 0);

signal internal_scaler_array : scaler_array_type;
signal latched_scaler_array : scaler_array_type; --//assigned after refresh pulse

	--//need to create a single pulse every Hz with width of 10 MHz clock period
	signal refresh_clk_counter_100Hz 	:	std_logic_vector(27 downto 0) := (others=>'0');
	signal refresh_clk_counter_1Hz 	:	std_logic_vector(27 downto 0) := (others=>'0');
	signal refresh_clk_counter_100mHz:	std_logic_vector(27 downto 0) := (others=>'0');
	signal refresh_clk_100Hz				:	std_logic := '0';
	signal refresh_clk_1Hz				:	std_logic := '0';
	signal refresh_clk_100mHz			:	std_logic := '0';
	--//for 10 MHz
	constant REFRESH_CLK_MATCH_100Hz 		: 	std_logic_vector(27 downto 0) := x"0002710"; --this is 1KHz;  
	--constant REFRESH_CLK_MATCH_100Hz 		: 	std_logic_vector(27 downto 0) := x"00186A0";  
	constant REFRESH_CLK_MATCH_1HZ 		: 	std_logic_vector(27 downto 0) 	:= x"0989680";  
	constant REFRESH_CLK_MATCH_100mHz 	: 	std_logic_vector(27 downto 0) 	:= x"5F5E100";  	
component scaler
port(
	rst_i 		: in 	std_logic;
	clk_i			: in	std_logic;
	refresh_i	: in	std_logic;
	count_i		: in	std_logic;
	scaler_o		: out std_logic_vector(scaler_width-1 downto 0));
end component;
-------------------------------------------------------------------------------
begin
-------------------------------------------------------------------------------
--proc_assign_scalers_to_metadata : running_scalers_o <= internal_scaler_array(32) & internal_scaler_array(0);
-------------------------------------------------------------------------------
--//scalers 0-11
CoincTrigScalers1Hz : for i in 0 to 11 generate
	xCOINC1Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_1Hz,
		count_i => coinc_trig_bits_i(i),
		scaler_o => internal_scaler_array(i));
end generate;
--//scalers 12-23
CoincTrigScalers100Hz : for i in 0 to 11 generate
	xCOINC100Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_100Hz,
		count_i => coinc_trig_bits_i(i),
		scaler_o => internal_scaler_array(i+12));
end generate;
-------------------------------------		
proc_save_scalers : process(rst_i, clk_i, reg_i)
begin
	if rst_i = '1' then
		for i in 0 to num_scalers-1 loop
			latched_scaler_array(i) <= (others=>'0');
		end loop;
		scaler_to_read_o <= (others=>'0');
		pps_timestamp_latched_o <= (others=>'0');
	
	elsif rising_edge(clk_i) and reg_i(40)(0) = '1' then
		latched_scaler_array <= internal_scaler_array;
		pps_timestamp_latched_o <= pps_timestamp_i;
		
	elsif rising_edge(clk_i) then
		case reg_i(41)(7 downto 0) is
			when x"00" =>
				scaler_to_read_o <= latched_scaler_array(1) & latched_scaler_array(0);
			when x"01" =>
				scaler_to_read_o <= latched_scaler_array(3) & latched_scaler_array(2);
			when x"02" =>
				scaler_to_read_o <= latched_scaler_array(5) & latched_scaler_array(4);
			when x"03" =>
				scaler_to_read_o <= latched_scaler_array(7) & latched_scaler_array(6);
			when x"04" =>
				scaler_to_read_o <= latched_scaler_array(9) & latched_scaler_array(8);
			when x"05" =>
				scaler_to_read_o <= latched_scaler_array(11) & latched_scaler_array(10);
			when x"06" =>
				scaler_to_read_o <= latched_scaler_array(13) & latched_scaler_array(12);
			when x"07" =>
				scaler_to_read_o <= latched_scaler_array(15) & latched_scaler_array(14);
			when x"08" =>
				scaler_to_read_o <= latched_scaler_array(17) & latched_scaler_array(16);
			when x"09" =>
				scaler_to_read_o <= latched_scaler_array(19) & latched_scaler_array(18);
			when x"0A" =>
				scaler_to_read_o <= latched_scaler_array(21) & latched_scaler_array(20);
			when x"0B" =>
				scaler_to_read_o <= latched_scaler_array(23) & latched_scaler_array(22);
			when x"0C" =>
				scaler_to_read_o <= latched_scaler_array(25) & latched_scaler_array(24);
			when x"0D" =>
				scaler_to_read_o <= latched_scaler_array(27) & latched_scaler_array(26);
			when x"0E" =>
				scaler_to_read_o <= latched_scaler_array(29) & latched_scaler_array(28);
			when x"0F" =>
				scaler_to_read_o <= latched_scaler_array(31) & latched_scaler_array(30);	
			when x"10" =>
				scaler_to_read_o <= latched_scaler_array(33) & latched_scaler_array(32);
			when x"11" =>
				scaler_to_read_o <= latched_scaler_array(35) & latched_scaler_array(34);
			when x"12" =>
				scaler_to_read_o <= latched_scaler_array(37) & latched_scaler_array(36);
			when x"13" =>
				scaler_to_read_o <= latched_scaler_array(39) & latched_scaler_array(38);
			when x"14" =>
				scaler_to_read_o <= latched_scaler_array(41) & latched_scaler_array(40);
			when x"15" =>
				scaler_to_read_o <= latched_scaler_array(43) & latched_scaler_array(42);
			when x"16" =>
				scaler_to_read_o <= latched_scaler_array(45) & latched_scaler_array(44);
			when x"17" =>
				scaler_to_read_o <= latched_scaler_array(47) & latched_scaler_array(46);
			when x"18" =>
				scaler_to_read_o <= latched_scaler_array(49) & latched_scaler_array(48);
			when x"19" =>
				scaler_to_read_o <= latched_scaler_array(51) & latched_scaler_array(50);	
			when x"1A" =>
				scaler_to_read_o <= latched_scaler_array(53) & latched_scaler_array(52);				
			when others =>
				scaler_to_read_o <= latched_scaler_array(1) & latched_scaler_array(0);
		end case;
	end if;
end process;

-------------------------------------------------------------------
--//make 1 Hz and 100mHz refresh pulses from the main iface clock (10 MHz)
proc_make_refresh_pulse : process(clk_i)
begin
	if rising_edge(clk_i) then
		
		if refresh_clk_1Hz = '1' then
			refresh_clk_counter_1Hz <= (others=>'0');
		else
			refresh_clk_counter_1Hz <= refresh_clk_counter_1Hz + 1;
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_1Hz is
			when REFRESH_CLK_MATCH_1HZ =>
				refresh_clk_1Hz <= '1';
			when others =>
				refresh_clk_1Hz <= '0';
		end case;
		
		--//////////////////////////////////////
		
		if refresh_clk_100mHz = '1' then
			refresh_clk_counter_100mHz <= (others=>'0');
		else
			refresh_clk_counter_100mHz <= refresh_clk_counter_100mHz + 1;
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_100mHz is
			when REFRESH_CLK_MATCH_100mHz =>
				refresh_clk_100mHz <= '1';
			when others =>
				refresh_clk_100mHz <= '0';
		end case;
		
		--//////////////////////////////////////
		
		if refresh_clk_100Hz = '1' then
			refresh_clk_counter_100Hz <= (others=>'0');
		else
			refresh_clk_counter_100Hz <= refresh_clk_counter_100Hz + 1;
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_100Hz is
			when REFRESH_CLK_MATCH_100Hz =>
				refresh_clk_100Hz <= '1';
			when others =>
				refresh_clk_100Hz <= '0';
		end case;
		
	end if;
end process;
end rtl;