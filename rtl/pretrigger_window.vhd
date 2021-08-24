---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      phased-array trigger board
-- FILE:         pretrigger_window.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         7/2017, 
--               added another buffer on 9/2017. Update 2021 for FLOWER board op.
--
-- DESCRIPTION:  data buffering to allow for pre-trigger time window
--               
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity pretrigger_window is
	generic(
		data_width			:  integer := 64);
	port(
		rst_i					:	in	 std_logic;
		clk_i					:  in	 std_logic;
		pretrig_sel_i		:	in	 std_logic_vector(3 downto 0);
		data_i				:	in	 std_logic_vector(data_width-1 downto 0);
		data_o				:	out std_logic_vector(data_width-1 downto 0));
	end pretrigger_window;
	
--/
--//HMCAD data chunk is 64 bits wide ==> 2ch w/ 4x 8bit words. clk_i is 118MHz
--//this module buffers these data to allow the system to save waveform information from
--//before the trigger signal..

architecture rtl of pretrigger_window is
	--//8-deep buffering, 4 samples/channel/chunk @ 472MSa/s
	--//   ===> ~67.8 ns pre-trig delay per pretrig_sel_i index
	type internal_data_buffer_type is array(7 downto 0) of std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_0 : internal_data_buffer_type;
	signal internal_data_buffer_1 : internal_data_buffer_type;
	signal internal_data_buffer_2 : internal_data_buffer_type;
	signal internal_data_buffer_3 : internal_data_buffer_type;
	signal internal_data_buffer_4 : internal_data_buffer_type;
	signal internal_data_buffer_5 : internal_data_buffer_type;
	signal internal_data_buffer_6 : internal_data_buffer_type;
	signal internal_data_buffer_7 : internal_data_buffer_type;

	signal internal_data_buffer_pickoff_0 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_1 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_2 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_3 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_4 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_5 : std_logic_vector(data_width-1 downto 0);	
	signal internal_data_buffer_pickoff_6 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_7 : std_logic_vector(data_width-1 downto 0);
	signal internal_data_buffer_pickoff_8 : std_logic_vector(data_width-1 downto 0);

	signal internal_data_pipe : std_logic_vector(data_width-1 downto 0);

begin

proc_buf_dat : process(rst_i, clk_i, data_i, internal_data_buffer_0, internal_data_buffer_1,
								internal_data_buffer_2, internal_data_buffer_3, internal_data_buffer_4)
begin
	if rst_i = '1' then
		for i in 0 to 7 loop
			internal_data_buffer_0(i) <= (others=>'0');
			internal_data_buffer_1(i) <= (others=>'0');
			internal_data_buffer_2(i) <= (others=>'0');
			internal_data_buffer_3(i) <= (others=>'0');
			internal_data_buffer_4(i) <= (others=>'0');
			internal_data_buffer_5(i) <= (others=>'0');
			internal_data_buffer_6(i) <= (others=>'0');
			internal_data_buffer_7(i) <= (others=>'0');

		end loop;
		
		internal_data_buffer_pickoff_0 <= (others=>'0');
		internal_data_buffer_pickoff_1 <= (others=>'0');
		internal_data_buffer_pickoff_2 <= (others=>'0');
		internal_data_buffer_pickoff_3 <= (others=>'0');
		internal_data_buffer_pickoff_4 <= (others=>'0');
		internal_data_buffer_pickoff_5 <= (others=>'0');
		internal_data_buffer_pickoff_6 <= (others=>'0');
		internal_data_buffer_pickoff_7 <= (others=>'0');
		internal_data_buffer_pickoff_8 <= (others=>'0');

		internal_data_pipe <= (others=>'0');
	
	elsif rising_edge(clk_i) then
		
		for i in 1 to 7 loop
			internal_data_buffer_7(i) <= internal_data_buffer_7(i-1);
			internal_data_buffer_6(i) <= internal_data_buffer_6(i-1);
			internal_data_buffer_5(i) <= internal_data_buffer_5(i-1);
			internal_data_buffer_4(i) <= internal_data_buffer_4(i-1);
			internal_data_buffer_3(i) <= internal_data_buffer_3(i-1);
			internal_data_buffer_2(i) <= internal_data_buffer_2(i-1);
			internal_data_buffer_1(i) <= internal_data_buffer_1(i-1);
			internal_data_buffer_0(i) <= internal_data_buffer_0(i-1);
		end loop;
		
		--//keep max fanout to two:
		internal_data_buffer_pickoff_8  <= internal_data_buffer_7(7);
		internal_data_buffer_7(0) <= internal_data_buffer_6(7);
		internal_data_buffer_pickoff_7  <= internal_data_buffer_6(7);
		internal_data_buffer_6(0) <= internal_data_buffer_5(7);
		internal_data_buffer_pickoff_6  <= internal_data_buffer_5(7);
		internal_data_buffer_5(0) <= internal_data_buffer_4(7);
		internal_data_buffer_pickoff_5  <= internal_data_buffer_4(7);
		internal_data_buffer_4(0) <= internal_data_buffer_3(7);
		internal_data_buffer_pickoff_4  <= internal_data_buffer_3(7);
		internal_data_buffer_3(0) <= internal_data_buffer_2(7);
		internal_data_buffer_pickoff_3  <= internal_data_buffer_2(7);
		internal_data_buffer_2(0) <= internal_data_buffer_1(7);
		internal_data_buffer_pickoff_2  <= internal_data_buffer_1(7);
		internal_data_buffer_1(0) <= internal_data_buffer_0(7);
		internal_data_buffer_pickoff_1  <= internal_data_buffer_0(7);
		internal_data_buffer_0(0) <= internal_data_pipe;
		internal_data_buffer_pickoff_0  <=internal_data_pipe;
		internal_data_pipe <= data_i;
	
	end if;
end process;

proc_assign_data_o : process(rst_i, clk_i, pretrig_sel_i, internal_data_buffer_pickoff_0, internal_data_buffer_pickoff_1,
										internal_data_buffer_pickoff_2, internal_data_buffer_pickoff_3,
										internal_data_buffer_pickoff_4, internal_data_buffer_pickoff_5,
										internal_data_buffer_pickoff_6, internal_data_buffer_pickoff_7,
										internal_data_buffer_pickoff_8)
begin
	if rising_edge(clk_i) then
		case pretrig_sel_i is
		
			when "0000"=>
				data_o <= internal_data_buffer_pickoff_0; --//"0" pre-trigger delay (actually, 1 clk cycle)
			when "0001"=> 
				data_o <= internal_data_buffer_pickoff_1;
			when "0010"=>
				data_o <= internal_data_buffer_pickoff_2;
			when "0011"=>
				data_o <= internal_data_buffer_pickoff_3;
			when "0100"=>
				data_o <= internal_data_buffer_pickoff_4; --//from initial tests on 9/1/2017, '4' seems to be optimal
			when "0101"=>
				data_o <= internal_data_buffer_pickoff_5;
			when "0110"=>
				data_o <= internal_data_buffer_pickoff_6;
			when "0111"=>
				data_o <= internal_data_buffer_pickoff_7; 
			when "1000"=>
				data_o <= internal_data_buffer_pickoff_8; 
			when others=>
				data_o <= internal_data_buffer_pickoff_0;
		end case;
	end if;
end process;
end rtl;