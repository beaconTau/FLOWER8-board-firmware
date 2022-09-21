---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         simple_trigger.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         6/2021
--
-- DESCRIPTION:  coinc. trigger
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity simple_trigger is
generic(
		ENABLE_COINC_TRIG : std_logic := '1';
		--//trigger setting register: coinc trig enable is bit [8]
		trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
		--//base register for per-channel coincidence thresholds
		coinc_trig_reg_base	: std_logic_vector(7 downto 0):= x"57";
		--//reg for coinc trig params
		coinc_trig_param_reg	: std_logic_vector(7 downto 0):= x"5B";
		address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E"
		);

port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 
		clk_data_i	:	in		std_logic; --data clock
		registers_i	:	in		register_array_type;
		pps_i			:  in		std_logic;
		pps_o			:	out	std_logic; -- delayed pps option
		
		ch0_data_i	: 	in		std_logic_vector(31 downto 0);
		ch1_data_i	:	in		std_logic_vector(31 downto 0);
		ch2_data_i	:	in		std_logic_vector(31 downto 0);
		ch3_data_i	:	in		std_logic_vector(31 downto 0);
		
		trig_bits_o : 	out	std_logic_vector(11 downto 0); --for scalers
		coinc_trig_o: 	out	std_logic --trigger
		);
end simple_trigger;

architecture rtl of simple_trigger is

type pps_delay_state_type is (idle, delay, pulse);
signal pps_delay_state : pps_delay_state_type;
signal internal_pps_trig_reg : std_logic_vector(1 downto 0); 
signal internal_pps_delay_counter : std_logic_vector(23 downto 0) := (others=>'0'); 

type threshold_array is array (3 downto 0) of std_logic_vector(7 downto 0);
signal trig_threshold_int	: threshold_array;
signal servo_threshold_int	: threshold_array;
signal coinc_require_int	: std_logic_vector(2 downto 0);
signal vppmode_int			: std_logic;

type streaming_data_array is array(3 downto 0) of std_logic_vector(63 downto 0);
signal streaming_data : streaming_data_array; --pipeline data
signal streaming_data_2 : streaming_data_array;

signal channel_trig_hi		: std_logic_vector(3 downto 0); --for hi/lo coinc
signal channel_trig_lo		: std_logic_vector(3 downto 0); --for hi/lo coinc
signal channel_servo_hi		: std_logic_vector(3 downto 0); --for hi/lo coinc
signal channel_servo_lo		: std_logic_vector(3 downto 0); --for hi/lo coinc
signal channel_trig_reg		: threshold_array;              --for coincidenc'ing
signal channel_servo_reg	: threshold_array;              --for coincidenc'ing

signal trig_clear				: std_logic_vector(3 downto 0);
signal servo_clear			: std_logic_vector(3 downto 0);
signal trig_counter			: threshold_array; --/not a threshold, but data type works
signal servo_counter			: threshold_array;

signal trig_array_for_scalers : std_logic_vector(11 downto 0); --//on clk_data_i

signal coincidence_trigger_reg : std_logic_vector(1 downto 0);
signal coincidence_trigger : std_logic; --actual trigger, one clk_data_i cycle
signal coincidence_servo_reg : std_logic_vector(1 downto 0);
signal coincidence_servo : std_logic; --one clk_data_i period

signal internal_coinc_trig_en : std_logic := '0'; --enable this trigger block from sw

signal coinc_window_int	: std_logic_vector(7 downto 0) := x"02"; --//num of clk_data_i periods
constant baseline			: std_logic_vector(7 downto 0) := x"80";

--------------
component signal_sync is
port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
end component;
component flag_sync is
port(
	clkA			: in	std_logic;
   clkB			: in	std_logic;
   in_clkA		: in	std_logic;
   busy_clkA	: out	std_logic;
   out_clkB		: out	std_logic);
end component;
--------------

begin
------------------------------------------------
--delayed pps trigger-out option
process(clk_i, rst_i, pps_i) -- slower 10MHz clock
begin
	if rst_i = '1' then
		internal_pps_trig_reg <= (others=>'0');
	elsif rising_edge(clk_data_i) then
		internal_pps_trig_reg <= internal_pps_trig_reg(0) & pps_i; --rising edge condition
	end if;
end process;
----
process(clk_i, rst_i)
begin
	if rst_i = '1' then
		pps_o <= '0';
		internal_pps_delay_counter <= (others=>'0');
		pps_delay_state <= idle;
	elsif rising_edge(clk_i) then
		case pps_delay_state is
			--idle
			when idle=>
				pps_o <= '0';
				internal_pps_delay_counter <= (others=>'0');
				if internal_pps_trig_reg = "01" then --pps_i rising-edge caught
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
------------------------------------------------
proc_pipeline_data : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		streaming_data(0)(63 downto 0) <= streaming_data(0)(31 downto 0) & ch0_data_i;
		streaming_data(1)(63 downto 0) <= streaming_data(1)(31 downto 0) & ch1_data_i;
		streaming_data(2)(63 downto 0) <= streaming_data(2)(31 downto 0) & ch2_data_i;
		streaming_data(3)(63 downto 0) <= streaming_data(3)(31 downto 0) & ch3_data_i;
		--second streaming array for pipelining
		streaming_data_2(0) <= streaming_data(0);
		streaming_data_2(1) <= streaming_data(1);
		streaming_data_2(2) <= streaming_data(2);
		streaming_data_2(3) <= streaming_data(3);
		
	end if;
end process;
------------------------------------------------
-- single channel trigger bits
proc_single_channel : process(clk_data_i, rst_i)
begin
for i in 0 to 3 loop
	if rst_i = '1' or ENABLE_COINC_TRIG = '0' then
		channel_servo_reg(i) 	<= (others=>'0');
		channel_trig_reg(i)	 	<= (others=>'0');
		channel_trig_lo(i) 		<= '0';
		channel_trig_hi(i) 		<= '0';
	elsif rising_edge(clk_data_i) and internal_coinc_trig_en = '0' then
		channel_servo_reg(i) 	<= (others=>'0');
		channel_trig_reg(i)	 	<= (others=>'0');
		channel_trig_lo(i) 		<= '0';
		channel_trig_hi(i) 		<= '0';
	elsif rising_edge(clk_data_i) then
		--lo-side threshold: take 4 samples + 2 sample overlap. This is a ~13 ns window, or thereabouts
		if streaming_data(i)(63 downto 56) <= (baseline - trig_threshold_int(i)) or 
			streaming_data(i)(55 downto 48) <= (baseline - trig_threshold_int(i)) or 
			streaming_data(i)(47 downto 40) <= (baseline - trig_threshold_int(i)) or 
			streaming_data(i)(39 downto 32) <= (baseline - trig_threshold_int(i)) or
			streaming_data(i)(31 downto 24) <= (baseline - trig_threshold_int(i)) or
			streaming_data(i)(23 downto 16) <= (baseline - trig_threshold_int(i)) then
			--
			channel_trig_lo(i) <= '1';
		else
			channel_trig_lo(i) <= '0';
		end if;
		--same for hi
		if streaming_data(i)(63 downto 56) >= (baseline + trig_threshold_int(i)) or 
			streaming_data(i)(55 downto 48) >= (baseline + trig_threshold_int(i)) or 
			streaming_data(i)(47 downto 40) >= (baseline + trig_threshold_int(i)) or 
			streaming_data(i)(39 downto 32) >= (baseline + trig_threshold_int(i)) or
			streaming_data(i)(31 downto 24) >= (baseline + trig_threshold_int(i)) or
			streaming_data(i)(23 downto 16) >= (baseline + trig_threshold_int(i)) then
			--
			channel_trig_hi(i) <= '1';
		else
			channel_trig_hi(i) <= '0';
		end if;
		--single-channel coinc, though a clear takes priority:
		if trig_clear(i) = '1' then
				channel_trig_reg(i)(0) <= '0';
		elsif channel_trig_lo(i) = '1' and channel_trig_hi(i) = '1' and vppmode_int = '1' then
				channel_trig_reg(i)(0) <= '1';
		elsif channel_trig_lo(i) = '1' and vppmode_int = '0' then
				channel_trig_reg(i)(0) <= '1';
		end if;
		--------------------
		--servo thresholding, using `streaming_data_2'
		--lo-side threshold: take 4 samples + 2 sample overlap. This is a ~13 ns window, or thereabouts
		if streaming_data_2(i)(63 downto 56) <= (baseline - servo_threshold_int(i)) or 
			streaming_data_2(i)(55 downto 48) <= (baseline - servo_threshold_int(i)) or 
			streaming_data_2(i)(47 downto 40) <= (baseline - servo_threshold_int(i)) or 
			streaming_data_2(i)(39 downto 32) <= (baseline - servo_threshold_int(i)) or
			streaming_data_2(i)(31 downto 24) <= (baseline - servo_threshold_int(i)) or
			streaming_data_2(i)(23 downto 16) <= (baseline - servo_threshold_int(i)) then
			--
			channel_servo_lo(i) <= '1';
		else
			channel_servo_lo(i) <= '0';
		end if;
		--same for hi
		if streaming_data_2(i)(63 downto 56) >= (baseline + servo_threshold_int(i)) or 
			streaming_data_2(i)(55 downto 48) >= (baseline + servo_threshold_int(i)) or 
			streaming_data_2(i)(47 downto 40) >= (baseline + servo_threshold_int(i)) or 
			streaming_data_2(i)(39 downto 32) >= (baseline + servo_threshold_int(i)) or
			streaming_data_2(i)(31 downto 24) >= (baseline + servo_threshold_int(i)) or
			streaming_data_2(i)(23 downto 16) >= (baseline + servo_threshold_int(i)) then
			--
			channel_servo_hi(i) <= '1';
		else
			channel_servo_hi(i) <= '0';
		end if;
		--single-channel coinc:
		if servo_clear(i) = '1' then
				channel_servo_reg(i)(0) <= '0';
		elsif channel_servo_lo(i) = '1' and channel_servo_hi(i) = '1' and vppmode_int = '1' then
				channel_servo_reg(i)(0) <= '1';
		elsif channel_servo_lo(i) = '1' and vppmode_int = '0' then
				channel_servo_reg(i)(0) <= '1';
		end if;
		----------------------------------------------
	
	end if;
end loop;
end process;
------------------------------------------------
--coinc window
proc_coinc_trig : process(rst_i, clk_data_i)
begin
	if rst_i = '1' then
		coincidence_trigger_reg <= "00";
		coincidence_trigger <= '0'; -- the trigger

		coincidence_servo_reg <= "00";
		coincidence_servo <= '0';  --the servo trigger

		for i in 0 to 3 loop
			trig_clear(i) <= '0';
			trig_counter(i) <= (others=>'0');
			servo_clear(i) <= '0';
			servo_counter(i) <= (others=>'0');
		end loop;
		
	elsif rising_edge(clk_data_i) then
		--loop over the channels
		for i in 0 to 3 loop
			if trig_counter(i) = coinc_window_int then
				trig_clear(i) <= '1';
			else
				trig_clear(i) <= '0';
			end if;
				
			if channel_trig_reg(i)(0) = '1' then
				trig_counter(i) <= trig_counter(i) + 1;
			else
				trig_counter(i) <= (others=>'0');
			end if;
			------------------------------------
			--for servoing only (basically a separate thresholding)
			if servo_counter(i) = coinc_window_int then
				servo_clear(i) <= '1';
			else
				servo_clear(i) <= '0';
			end if;
				
			if channel_servo_reg(i)(0) = '1' then
				servo_counter(i) <= servo_counter(i) + 1;
			else
				servo_counter(i) <= (others=>'0');
			end if;
			------------------------------------
		end loop;
		
		--//coinc requirement. Note that 1 channel required for trigger when 'coinc_require_int' == 0
		if to_integer(unsigned(channel_trig_reg(0))) + to_integer(unsigned(channel_trig_reg(1))) + 
			to_integer(unsigned(channel_trig_reg(2))) + to_integer(unsigned(channel_trig_reg(3))) > to_integer(unsigned(coinc_require_int)) then
			
			coincidence_trigger_reg(0) <= '1';
		
		else
			coincidence_trigger_reg(0) <= '0';
		end if;
		
		coincidence_trigger_reg(1) <= coincidence_trigger_reg(0); --dumb way to trigger on "01", rising edge
		if coincidence_trigger_reg = "01" then
			coincidence_trigger <= '1';
		else
			coincidence_trigger <= '0';
		end if;
		----------------------servo----------------------------------------------------------------------
		--//coinc requirement. Note that 1 channel required for trigger when 'coinc_require_int' == 0
		if to_integer(unsigned(channel_servo_reg(0))) + to_integer(unsigned(channel_servo_reg(1))) + 
			to_integer(unsigned(channel_servo_reg(2))) + to_integer(unsigned(channel_servo_reg(3))) > to_integer(unsigned(coinc_require_int)) then
			
			coincidence_servo_reg(0) <= '1';
		
		else
			coincidence_servo_reg(0) <= '0';
		end if;
		
		coincidence_servo_reg(1) <= coincidence_servo_reg(0); --dumb way to trigger on "01", rising edge
		if coincidence_servo_reg = "01" then
			coincidence_servo <= '1';
		else
			coincidence_servo <= '0';
		end if;
	end if;
end process;
		
--//sync some software commands to the data clock
TRIG_THRESHOLDS : for j in 0 to 3 generate
	INDIV_TRIG_BITS : for i in 0 to 7 generate
		xTRIGTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(coinc_trig_reg_base))+j)(i), --threshold from software
		SignalOut_clkB	=> trig_threshold_int(j)(i));
	end generate;
end generate;
--------------
SERVO_THRESHOLDS : for j in 0 to 3 generate
	INDIV_SERVO_BITS : for i in 0 to 7 generate
		xSERVOTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(coinc_trig_reg_base))+j)(i+8), --threshold from software
		SignalOut_clkB	=> servo_threshold_int(j)(i));
	end generate;
end generate;
--------------
COINCREQ : for i in 0 to 2 generate
	xCOINCREQSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(coinc_trig_param_reg)))(i), --num_coinc_requirement (0,1,2 or 3)
		SignalOut_clkB	=> coinc_require_int(i));
end generate;
COINCWIN : for i in 0 to 7 generate
	xCOINCWINSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(coinc_trig_param_reg)))(i+8), --coinc_window size
		SignalOut_clkB	=> coinc_window_int(i));
end generate;
xVPPMODESYNC : signal_sync
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(coinc_trig_param_reg)))(16), --vppmode
	SignalOut_clkB	=> vppmode_int);
--------------
trig_array_for_scalers <= "00" & servo_clear(3) & servo_clear(2) &
									servo_clear(1) & servo_clear(0) & coincidence_servo &
									trig_clear(3) & trig_clear(2) & trig_clear(1) & 
									trig_clear(0) & coincidence_trigger;
----TRIGGER OUT!!
coinc_trig_o <= coincidence_trigger_reg(0); --use the variable-width reg signal instead of the coincidence_trigger to save 1 clk cycle of delay
--------------
TrigToScalers	:	 for i in 0 to 11 generate
	xTRIGSYNC : flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> trig_array_for_scalers(i),
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(i));
end generate TrigToScalers;
--------------
xTRIGENABLESYNC : signal_sync
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(trigger_enable_reg_adr)))(8), --overall coinc trig enable bit
	SignalOut_clkB	=> internal_coinc_trig_en);
end rtl;