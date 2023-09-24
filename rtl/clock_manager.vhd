---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         clock_manager.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         1/2021
--
-- DESCRIPTION:  clocks, top level manager
--
---------------------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity clock_manager is
	Port(
		Reset_i			:  in		std_logic;
		CLK0_i			:	in		std_logic; --//10MHz on-board clock
		CLK1_i			:  in		std_logic;
		PLL_reset_i		:  in		std_logic;
		
		CLK_2MHz_o		:  out	std_logic;
		CLK_10MHz_loc_o:  out	std_logic;
		CLK_20MHz_loc_o:	out	std_logic;
		CLK_20MHz_sys_o:  out	std_logic;
		CLK_core_sys_o :  out	std_logic; --*125.00MHz, with 8-chan firmware
		CLK_1Hz_o		:  out	std_logic;
		CLK_10Hz_o		:  out	std_logic;
		CLK_1kHz_o		:	out	std_logic;
		CLK_100kHz_o	:	out	std_logic;

		fpga_pll1lock_o : inout std_logic;
		fpga_pll2lock_o :	inout	std_logic);  --lock signal from main PLL on fpga

end clock_manager;

architecture rtl of clock_manager is
	
	signal clk_2MHz_sig			: 	std_logic;
	signal clk_10MHz_loc_sig	: 	std_logic;
	signal clk_20MHz_loc_sig	: 	std_logic;
	signal clk_20MHz_sys_sig	: 	std_logic;
	
	--//PLL derived from board-clock:
	component pll_block_1
		port( refclk, rst			: in 	std_logic;
				outclk_0, outclk_1, outclk_2, locked : out	std_logic);
	end component;
	--//PLL derived from system clock:
	component pll_block_2
		port( refclk, rst			: in 	std_logic;
				outclk_0, outclk_1, locked : out	std_logic);
	end component;
	--//PLL derived from external system-clock:
	component slow_clocks
		generic(clk_divide_by   : integer := 500);
		port( clk_i, Reset_i		: in	std_logic;
				clk_o					: out	std_logic);
	end component;	
	
begin
	CLK_2MHz_o			<=	clk_2MHz_sig;
	CLK_10MHz_loc_o	<= clk_10MHz_loc_sig;
	CLK_20MHz_loc_o	<= clk_20MHz_loc_sig;
	CLK_20MHz_sys_o	<= clk_20MHz_sys_sig;

	
	xPLL_BLOCK1 : pll_block_1
		port map(CLK0_i, '0', clk_2MHz_sig, clk_10MHz_loc_sig, clk_20MHz_loc_sig, fpga_pll1lock_o );
	xPLL_BLOCK2 : pll_block_2
		port map(CLK1_i, '0', clk_20MHz_sys_sig, CLK_core_sys_o, fpga_pll2lock_o );				
	xCLK_GEN_100kHz : slow_clocks
		generic map(clk_divide_by => 10)
		port map(clk_2MHz_sig, Reset_i, CLK_100kHz_o);
	
	xCLK_GEN_1kHz : slow_clocks
		generic map(clk_divide_by => 1000)
		port map(clk_2MHz_sig, Reset_i, CLK_1kHz_o);

	xCLK_GEN_10Hz : slow_clocks
		generic map(clk_divide_by => 100000)
		port map(clk_2MHz_sig, Reset_i, CLK_10Hz_o);
		
	xCLK_GEN_1Hz : slow_clocks
		generic map(clk_divide_by => 1000000)
		port map(clk_2MHz_sig, Reset_i, CLK_1Hz_o);
		
	
	
end rtl;