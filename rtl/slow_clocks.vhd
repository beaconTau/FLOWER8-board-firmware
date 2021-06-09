---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      phased-array trigger board
-- FILE:         slow_clocks.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         1/2016
--
-- DESCRIPTION:  generate slow clocks for house-keeping
--
---------------------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity slow_clocks is
	generic (clk_divide_by : integer := 500);  -- default output is 1kHz
	
	port(		clk_i		:	in		std_logic;  --nominally 1MHz
				Reset_i	:	in		std_logic;	--active hi												
				clk_o		: 	out	std_logic);
				
end slow_clocks;

architecture rtl of slow_clocks is
	type		STATE_TYPE 	is (CLK_HI, CLK_LO);
	signal	xCLK_STATE	:	STATE_TYPE;
	signal	xOUT_CLK		:	std_logic;
	
begin

	clk_o <= xOUT_CLK;

	process(clk_i, Reset_i)
	variable i: integer range clk_divide_by downto 0 := 0;
	begin
		
		if	Reset_i = '1' then
			xOUT_CLK		<= '0';
			i 				:=  0;
			xCLK_STATE	<= CLK_HI;
			
		elsif rising_edge(clk_i) then
		
			case xCLK_STATE is
				
					when CLK_HI =>
						xOUT_CLK <= '1';
						i 	:= i + 1;
						
						if i = clk_divide_by then
							i	:= 0;
							xCLK_STATE <= CLK_LO;	
						end if;
							
					when CLK_LO =>
						xOUT_CLK <= '0';
						i 	:= i + 1;
						
						if i = clk_divide_by then
							i	:= 0;
							xCLK_STATE <= CLK_HI;	
						end if;
			
					when others =>
						xCLK_STATE <= CLK_LO;	
				
			end case;
		end if;
	end process;
	
end rtl;

	