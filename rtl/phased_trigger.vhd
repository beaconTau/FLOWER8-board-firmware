---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      BEACON Flower-8
-- FILE:         phased_trigger.vhd
-- AUTHOR:       Ryan Krebs
-- EMAIL         rjk5416@psu.edu
-- DATE:         2/24
--
-- DESCRIPTION:  phased trigger
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;

use work.defs.all;

entity phased_trigger is
generic(
		ENABLE_PHASED_TRIG : std_logic := '1';
		--//trigger setting register: coinc trig enable is bit [8]
		trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
		--//base register for per-channel coincidence thresholds
		phased_trig_reg_base	: std_logic_vector(7 downto 0):= x"50";
		phased_trig_reg_base_extra: std_logic_vector(7 downto 0):=x"80";
		phased_trig_param_reg	: std_logic_vector(7 downto 0):= x"81";
		address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E" ;
		beam_mask_reg : std_logic_vector(7 downto 0) := x"62"
		);

port(
		rst_i			:	in		std_logic;
		clk_i			:	in		std_logic; --register clock 
		clk_data_i	:	in		std_logic; --data clock
		registers_i	:	in		register_array_type;
		
		ch0_data_i	: 	in		std_logic_vector(31 downto 0);
		ch1_data_i	:	in		std_logic_vector(31 downto 0);
		ch2_data_i	:	in		std_logic_vector(31 downto 0);
		ch3_data_i	:	in		std_logic_vector(31 downto 0);
		ch4_data_i	: 	in		std_logic_vector(31 downto 0);
		ch5_data_i	:	in		std_logic_vector(31 downto 0);
		ch6_data_i	:	in		std_logic_vector(31 downto 0);
		ch7_data_i	:	in		std_logic_vector(31 downto 0);
		
		last_trig_bits_latched_o : out std_logic_vector(num_beams-1 downto 0); --for metadata
		trig_bits_o : 	out	std_logic_vector(2*(num_beams+1) downto 0); --for scalers
		phased_trig_o: 	out	std_logic --trigger
		);
end phased_trigger;

architecture rtl of phased_trigger is 

constant streaming_buffer_length: integer := 70;
constant window_length:integer := 16;
constant baseline: signed(7 downto 0) := x"80";
constant phased_sum_bits: integer := 8;
constant phased_sum_length: integer := 24; --not sure if it should be 8 or 16. longer windows smooths things. shorter window gives higher peak
constant phased_sum_power_bits: integer := 16;
constant num_power_bits: integer := 24;
constant power_sum_bits:	integer := 24; --actually 25 but this fits into the io regs
constant input_power_thesh_bits:	integer := 12;
constant power_length: integer := 12;
constant power_low_bit: integer := 0; --might need to be 1. tried making it adjustable but didnt work. lab based sig starts triggering at 4000 threshold
constant power_high_bit: integer := power_low_bit+power_length-1;
constant num_div: integer := 4;--integer(log2(real(phased_sum_length)));
constant pad_zeros: std_logic_vector(num_div-1 downto 0):=(others=>'0');
constant num_channels: integer:=6;
--constant threshold_offset: integer:= 3000; --if this works I can add it to the registers. might not work

signal threshold_offset: unsigned(11 downto 0):=x"000";

type antenna_delays is array (num_beams-1 downto 0,num_channels-1 downto 0) of integer;
--constant beam_delays : antenna_delays := ((12,11,10,9),(45,45,45,45)); --it will optimize away a lot of the streaming buffer if these numbers are small
constant beam_delays : antenna_delays := (others=>(others=>32)); --try to force only beam 0 to trigger

--(7,26,47,68),(7,25,45,65),(7,24,43,61),(7,23,40,57),(7,21,37,53),(7,20,34,48),(7,18,31,43),(7,16,28,37),(7,15,24,32),(7,13,21,27),(7,11,18,21),(7,10,15,17),(7,8,12,12),(7,7,9,8),(9,8,9,7),(12,10,10,7),


--constant beam_delays : antenna_delays := ((4,23,44,65),(4,22,42,62),(4,21,40,58),(4,20,37,54),(4,18,34,50),(4,17,31,45),(4,15,28,40),(4,13,25,34),(4,12,21,29),(4,10,18,24),(4,8,15,18),(4,7,12,14),(4,5,9,9),(4,4,6,5),(6,5,6,4),(9,7,7,4));
-- 8 beams!!! signal beam_delays: antenna_delays:=(4,23,44,65),(4,21,40,58),(4,18,34,48),(4,14,27,37),(4,11,19,26),(4,7,12,15),(4,4,6,5),(9,7,7,4));
--honestly might be useful to add a beam of zero delay. the above have cable delays included into the calc


type thresh_input is array (num_beams-1 downto 0) of unsigned(input_power_thesh_bits-1 downto 0);
signal input_trig_thresh : thresh_input;
signal input_servo_thresh : thresh_input;

--type streaming_data_array is array(7 downto 0) of std_logic_vector((streaming_buffer_length*8-1) downto 0);
--signal streaming_data : streaming_data_array := (others=>(others=>'0')); --pipeline data

type streaming_data_array is array(num_channels-1 downto 0, streaming_buffer_length-1 downto 0) of signed(7 downto 0);
signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

type phased_arr_buff is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of signed(phased_sum_bits+1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves_buff: phased_arr_buff;

type phased_arr is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of signed(phased_sum_bits-1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves: phased_arr;

type square_waveform is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of unsigned(phased_sum_power_bits-1 downto 0);-- range 0 to 2**phased_sum_power_bits-1;--std_logic_vector(phased_sum_power_bits-1 downto 0);
signal phased_power : square_waveform;

type power_array is array (num_beams-1 downto 0) of unsigned(num_power_bits-1 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
signal trig_beam_thresh : power_array:=(others=>(others=>'0')) ; --trigger thresholds for all beams
signal servo_beam_thresh : power_array:=(others=>(others=>'0')) ;--(others=>(others=>'0')) --servo thresholds for all beams
signal power_sum : power_array; --power levels for all beams
signal power_sum0: power_array;
signal power_sum1: power_array;
signal avg_power: power_array;
signal latched_power_out: power_array;

signal triggering_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');
signal servoing_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');

signal phased_trigger : std_logic;
signal phased_trigger_reg : std_logic_vector(1 downto 0);

type trigger_regs is array(num_beams-1 downto 0) of std_logic_vector(1 downto 0);
signal beam_trigger_reg : trigger_regs;
signal beam_servo_reg : trigger_regs;

signal phased_servo : std_logic;
signal phased_servo_reg : std_logic_vector(1 downto 0);

type trigger_counter is array (num_beams-1 downto 0) of unsigned(15 downto 0);

signal trig_clear				: std_logic_vector(num_beams-1 downto 0);
signal servo_clear			: std_logic_vector(num_beams-1 downto 0);
signal trig_counter			: trigger_counter:= (others=>(others=>'0'));
signal servo_counter			: trigger_counter:= (others=>(others=>'0'));

signal last_trig_bits_latched : std_logic_vector(num_beams-1 downto 0);

signal trig_array_for_scalers : std_logic_vector(2*(num_beams+1) downto 0); --//on clk_data_i

signal internal_phased_trig_en : std_logic := '0'; --enable this trigger block from sw
signal internal_trigger_channel_mask : std_logic_vector(7 downto 0);
signal internal_trigger_beam_mask : std_logic_vector(num_beams-1 downto 0);
signal bits_for_trigger : std_logic_vector(num_beams-1 downto 0);
signal trig_array_for_scalars : std_logic_vector (2*(num_beams+1)-1 downto 0);

constant coinc_window_int	: integer := 1; --//num of clk_data_i periods

signal is_there_a_trigger: std_logic_vector(num_beams-1 downto 0);
signal is_there_a_servo: std_logic_vector(num_beams-1 downto 0);

signal trig_bits_metadata: std_logic_vector(num_beams-1 downto 0);

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


proc_convert_thresholds : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
			trig_beam_thresh(i)(power_high_bit downto power_low_bit)<=input_trig_thresh(i);
			servo_beam_thresh(i)(power_high_bit downto power_low_bit)<=input_servo_thresh(i);
		end loop;
			
	end if;
end process;
	
proc_pipeline_data : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		--streaming_buffer_length is an excessive value for trying to get a trigger out and recording data.
			
		streaming_data(0,1)<=signed(ch0_data_i(15 downto 8))-baseline;
		streaming_data(0,0)<=signed(ch0_data_i(7 downto 0))-baseline;
			
		streaming_data(1,1)<=signed(ch1_data_i(15 downto 8))-baseline;
		streaming_data(1,0)<=signed(ch1_data_i(7 downto 0))-baseline;
		
		streaming_data(2,1)<=signed(ch4_data_i(15 downto 8))-baseline;
		streaming_data(2,0)<=signed(ch4_data_i(7 downto 0))-baseline;
		

		streaming_data(3,1)<=signed(ch5_data_i(15 downto 8))-baseline;
		streaming_data(3,0)<=signed(ch5_data_i(7 downto 0))-baseline;

		streaming_data(4,1)<=signed(ch6_data_i(15 downto 8))-baseline;
		streaming_data(4,0)<=signed(ch6_data_i(7 downto 0))-baseline;
			
		streaming_data(5,1)<=signed(ch7_data_i(15 downto 8))-baseline;
		streaming_data(5,0)<=signed(ch7_data_i(7 downto 0))-baseline;
			
		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(0,i)<=streaming_data(0,i-2);
		end loop;

		
		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(1,i)<=streaming_data(1,i-2);
		end loop;

		
		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(2,i)<=streaming_data(2,i-2);
		end loop;

		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(3,i)<=streaming_data(3,i-2);
		end loop;
		
		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(4,i)<=streaming_data(4,i-2);
		end loop;
		
		for i in 2 to streaming_buffer_length-1 loop
			streaming_data(5,i)<=streaming_data(5,i-2);
		end loop;
		
	end if;
end process;
------------------------------------------------

proc_phasing : process(clk_data_i,rst_i)
begin

	if rising_edge(clk_data_i) and internal_phased_trig_en = '0'then
		--phase waveforms
		for i in 0 to num_beams-1 loop --loop over beams
			for j in 0 to phased_sum_length-1 loop
				--phased_beam_waves(i*phased_sum_length+j) <= unsigned(streaming_data(0)(beam_delays(i*num_channels)+4 downto beam_delays(i*num_channels)-4)) 
				phased_beam_waves_buff(i,j)<=resize(streaming_data(0,beam_delays(i,0)-(j-11)),10)
					+resize(streaming_data(1,beam_delays(i,1)-(j-7)),10)
					+resize(streaming_data(2,beam_delays(i,2)-(j-7)),10)
					+resize(streaming_data(3,beam_delays(i,1)-(j-7)),10)
					+resize(streaming_data(4,beam_delays(i,2)-(j-7)),10)
					+resize(streaming_data(5,beam_delays(i,3)-(j-7)),10);
					
				if(to_integer(phased_beam_waves_buff(i,j))>127) then
					phased_beam_waves(i,j)<=abs(b"01111111");--saturate max
				elsif(to_integer(phased_beam_waves_buff(i,j))<-127) then
				  phased_beam_waves(i,j)<=abs(b"10000000"); --saturate min
				else
					phased_beam_waves(i,j)<=abs(resize(phased_beam_waves_buff(i,j),8)); --this can be 10, 9 fits in a 1/4 of dsp. the rest of the calculations souldnt overflow
					--phased_beam_waves(i,j)<=phased_beam_waves_buff(i,j)(9)&phased_beam_waves_buff(i,j)(6 downto 0); --send it through
				end if;	

			end loop;
		end loop;

	end if;

end process;
------------------------------------------------
proc_do_beam_square : process(clk_data_i,rst_i)
begin

	if rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
			for j in 0 to phased_sum_length-1 loop
				phased_power(i,j)<=unsigned(phased_beam_waves(i,j))*unsigned(phased_beam_waves(i,j));
				
			end loop;
		end loop;
	
	end if;
end process;
------------------------------------------------
		
proc_do_beam_sum : process(clk_data_i,rst_i)
begin		


	if rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
				
				
			power_sum0(i)<=resize(phased_power(i,0),num_power_bits)+resize(phased_power(i,1),num_power_bits)+resize(phased_power(i,2),num_power_bits)
				+resize(phased_power(i,3),num_power_bits)+resize(phased_power(i,4),num_power_bits)+resize(phased_power(i,5),num_power_bits)
				+resize(phased_power(i,6),num_power_bits)+resize(phased_power(i,7),num_power_bits);
			power_sum1(i)<=resize(phased_power(i,8),num_power_bits)
				+resize(phased_power(i,9),num_power_bits)+resize(phased_power(i,10),num_power_bits)+resize(phased_power(i,11),num_power_bits)
				+resize(phased_power(i,12),num_power_bits)+resize(phased_power(i,13),num_power_bits)+resize(phased_power(i,14),num_power_bits)
				+resize(phased_power(i,15),num_power_bits);
			power_sum(i)<=power_sum0(i)+power_sum1(i);
	
			avg_power(i)(power_sum_bits-1 downto power_sum_bits-num_div)<=unsigned(pad_zeros);
			avg_power(i)(power_sum_bits-1-num_div downto 0)<=power_sum(i)(power_sum_bits-1 downto num_div); --divide by window size
		end loop;
	end if;
end process;

------------------------------------------------			
		
proc_get_triggering_beams : process(clk_data_i,rst_i)
begin
	if rst_i = '1' then
		phased_trigger_reg <= "00";
		phased_trigger <= '0'; -- the trigger

		phased_servo_reg <= "00";
		phased_servo <= '0';  --the servo trigger

		last_trig_bits_latched_o <= (others=>'0');
		triggering_beam<= (others=>'0');
		servoing_beam<= (others=>'0');
		
	elsif rising_edge(clk_data_i) then
		--loop over the beams and this is a big mess
		for i in 0 to num_beams-1 loop
			if avg_power(i)>trig_beam_thresh(i) then
				triggering_beam(i)<='1';
				beam_trigger_reg(i)(0)<='1';
				latched_power_out(i)<=avg_power(i);
			else
				triggering_beam(i)<='0';
				beam_trigger_reg(i)(0)<='0';
			end if;
			
			beam_trigger_reg(i)(1)<=beam_trigger_reg(i)(0);
			if avg_power(i)>servo_beam_thresh(i) then
				servoing_beam(i)<='1';
				beam_servo_reg(i)(0)<='1';
			else
				servoing_beam(i)<='0';
				beam_servo_reg(i)(0)<='0';
			end if;
			beam_servo_reg(i)(1)<=beam_servo_reg(i)(0);

		end loop;
		if (to_integer(unsigned(triggering_beam AND internal_trigger_beam_mask))>0) and (internal_phased_trig_en='1') then
			phased_trigger_reg(0)<='1';
			last_trig_bits_latched_o<=triggering_beam AND internal_trigger_beam_mask;
		else
			phased_trigger_reg(0)<='0';
		end if;
		if (to_integer(unsigned(servoing_beam AND internal_trigger_beam_mask))>0) and (internal_phased_trig_en='1') then
			phased_servo_reg(0)<='1';
		else
			phased_servo_reg(0)<='0';
		end if;
		
		phased_trigger_reg(1)<=phased_trigger_reg(0);
		phased_servo_reg(1)<=phased_servo_reg(0);

		if phased_trigger_reg="01" then
			phased_trigger<='1';

		else
			phased_trigger<='0';
		end if;
		
		if phased_servo_reg="01" then
			phased_servo<='1';
		else
			phased_servo<='0';
		end if;
	end if;
end process;
	
------------------------------------------------

--//sync some software commands to the data clock
TRIG_THRESHOLDS : for j in 0 to num_beams-1 generate
	INDIV_TRIG_BITS : for i in 0 to input_power_thesh_bits-1 generate
		xTRIGTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+j)(i), --threshold from software
		SignalOut_clkB	=> input_trig_thresh(j)(i));
	end generate;
end generate;

SERVO_THRESHOLDS : for j in 0 to num_beams-1 generate
	INDIV_SERVO_BITS : for i in 0 to input_power_thesh_bits-1 generate
		xSERVOTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+j)(i+12), --threshold from software
		SignalOut_clkB	=> input_servo_thresh(j)(i));
	end generate;
end generate;

------------
--TRIGBEAMMASKA : for i in 0 to num_beams-1 generate --beam masks. 1 == on
TRIGBEAMMASKA : for i in 0 to 23 generate --beam masks. 1 == on
	xTRIGBEAMMASKSYNC : signal_sync
	port map(
	clkA	=> clk_i,   clkB	=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base)))(i), --trig channel mask
	SignalOut_clkB	=> internal_trigger_beam_mask(i));
end generate;
TRIGBEAMMASKB : for i in 0 to num_beams-1-24 generate --beam masks. 1 == on
	xTRIGBEAMMASKSYNC : signal_sync
	port map(
	clkA	=> clk_i,   clkB	=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base_extra)))(i), --trig channel mask
	SignalOut_clkB	=> internal_trigger_beam_mask(i+24));
end generate;
------------

----TRIGGER OUT!!
phased_trig_o <= phased_trigger_reg(0); --phased trigger for 0->1 transition. phased_trigger_reg(0) for absolute trigger 
--------------
trigscaler: flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> phased_trigger,
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(0));

TrigToScalers	:	 for i in 0 to num_beams-1 generate 
	xTRIGSYNC : flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> triggering_beam(i) and internal_trigger_beam_mask(i),
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(i+1));
end generate TrigToScalers;


servoscaler: flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> phased_servo,
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(num_beams+1));

ServoToScalers	:	 for i in 0 to num_beams-1 generate 
	xSERVOSYNC : flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> servoing_beam(i) and internal_trigger_beam_mask(i),
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(i+num_beams+2));
end generate ServoToScalers;
--------------
xTRIGENABLESYNC : signal_sync --phased trig enable bit
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(trigger_enable_reg_adr)))(9), --overall coinc trig enable bit
	SignalOut_clkB	=> internal_phased_trig_en);
end rtl;