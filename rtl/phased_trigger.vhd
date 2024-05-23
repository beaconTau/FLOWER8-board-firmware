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
		trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
		--//base register for per-beam phased thresholds
		phased_trig_reg_base	: std_logic_vector(7 downto 0):= x"50";
		phased_trig_param_reg	: std_logic_vector(7 downto 0):= x"80";
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
		trig_bits_o : 	out	std_logic_vector(2*(num_beams+1)-1 downto 0); --for scalers
		phased_trig_o: 	out	std_logic --trigger
		);
end phased_trigger;

architecture rtl of phased_trigger is 

--general defines
constant baseline: signed(7 downto 0) := x"80";
constant num_channels: integer:=6;

--buffer & window lengths
constant streaming_buffer_length: integer := 70;
constant window_length:integer := 16;
constant phased_sum_length: integer := 16;

--data sizes
constant phased_sum_bits: integer := 8;
constant phased_sum_power_bits: integer := 16;
constant num_power_bits: integer := 20;
constant power_sum_bits:	integer := 16; 
constant input_power_thesh_bits:	integer := 12;

--threshold things
constant num_div: integer := 4;--integer(log2(real(phased_sum_length)));
constant pad_zeros: std_logic_vector(num_div-1 downto 0):=(others=>'0');
signal threshold_offset: unsigned(11 downto 0):=x"000";

type antenna_delays is array (num_beams-1 downto 0,num_channels-1 downto 0) of integer;
--constant beam_delays : antenna_delays := (others=>(others=>32)); --try to force only beam 0 to trigger

--8
--constant beam_delays: antenna_delays:= ((12,12,12,12,12,12),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
--	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8));
	
--12
--constant beam_delays: antenna_delays:= ((12,12,12,12,12,12),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
--	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8),(33,13,18,32,29,8),
--	(36,15,14,27,28,8),(38,16,10,21,26,8),(40,19,8,17,24,10));

--16	
--constant beam_delays: antenna_delays:= ((12,12,12,12,12,12),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
--	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8),(33,13,18,32,29,8),
--	(36,15,14,27,28,8),(38,16,10,21,26,8),(40,19,8,17,24,10),(15,8,20,29,22,8),(21,10,18,28,24,8),
--	(26,12,16,26,24,8),(29,13,13,22,23,8));
	
--20 beams with test
--constant beam_delays: antenna_delays:= ((12,12,12,12,12,12),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
--	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8),(33,13,18,32,29,8),
--	(36,15,14,27,28,8),(38,16,10,21,26,8),(40,19,8,17,24,10),(15,8,20,29,22,8),(21,10,18,28,24,8),
--	(26,12,16,26,24,8),(29,13,13,22,23,8),(31,15,9,17,21,8),(33,18,8,14,20,11),(11,8,18,23,17,9),
--	(15,9,15,21,17,8));

--20 beams real delays	
constant beam_delays: antenna_delays:= ((25,9,25,40,31,8),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8),(33,13,18,32,29,8),
	(36,15,14,27,28,8),(38,16,10,21,26,8),(40,19,8,17,24,10),(15,8,20,29,22,8),(21,10,18,28,24,8),
	(26,12,16,26,24,8),(29,13,13,22,23,8),(31,15,9,17,21,8),(33,18,8,14,20,11),(11,8,18,23,17,9),
	(15,9,15,21,17,8));
	
--constant beam_delays: antenna_delays:= ((25,9,25,40,31,8),(32,12,22,39,33,8),(38,14,19,36,33,8),(42,16,15,31,32,8),
--	(44,17,11,25,30,8),(45,20,8,19,27,9),(20,9,23,35,27,8),(27,11,21,34,29,8),(33,13,18,32,29,8),
--	(36,15,14,27,28,8),(38,16,10,21,26,8),(40,19,8,17,24,10),(15,8,20,29,22,8),(21,10,18,28,24,8),
--	(26,12,16,26,24,8),(29,13,13,22,23,8),(31,15,9,17,21,8),(33,18,8,14,20,11),(11,8,18,23,17,9),
--	(15,9,15,21,17,8),(18,10,13,19,18,8),(21,12,11,16,17,8),(22,13,8,12,16,8),(25,16,8,10,16,11));


	
--The input thresholds read from the 24 bit regs. 12 bits per threshold
type thresh_input is array (num_beams-1 downto 0) of unsigned(input_power_thesh_bits-1 downto 0);
signal input_trig_thresh : thresh_input ;
signal input_servo_thresh : thresh_input;

--streaming buffer for keeping samples for when they need to be used
type streaming_data_array is array(num_channels-1 downto 0, streaming_buffer_length-1 downto 0) of signed(7 downto 0);
signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

--temp coherent summed waveform buffer to keep at 10 bits and then resize to 7 bits
type phased_arr_buff is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of signed(9 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves_buff: phased_arr_buff;

--coherently summed waveform at 7 bits
type phased_arr is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of signed(6 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves: phased_arr;

--power of the coherently summed waveform
type square_waveform is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of unsigned(13 downto 0);-- range 0 to 2**phased_sum_power_bits-1;--std_logic_vector(phased_sum_power_bits-1 downto 0);
signal phased_power : square_waveform;

--the full threshold values (input + offset) expanded to the 16 bits, the full power sum, the 2 intermediary power sums, and finally the averaged power (power sum shifted down by 4 bits down)
type power_array is array (num_beams-1 downto 0) of unsigned(num_power_bits-1 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
signal trig_beam_thresh : power_array:=(others=>(others=>'0')) ; --trigger thresholds for all beams
signal servo_beam_thresh : power_array:=(others=>(others=>'0')) ;--(others=>(others=>'0')) --servo thresholds for all beams
signal power_sum : power_array; --power levels for all beams
signal power_sum0: power_array; --power sum of lower 8 samples
signal power_sum1: power_array; --power sum of upper 8 samples
signal avg_power: power_array;  --power_sum divided by window size (shifted down)
signal latched_power_out: power_array; --test for beam powers

--array to hold the triggering and servoing beams
signal triggering_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');
signal servoing_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');

signal phased_trigger : std_logic;
signal phased_trigger_reg : std_logic_vector(1 downto 0);

type trigger_regs is array(num_beams-1 downto 0) of std_logic_vector(1 downto 0);
signal beam_trigger_reg : trigger_regs;
signal beam_servo_reg : trigger_regs;

signal phased_servo : std_logic;
signal phased_servo_reg : std_logic_vector(1 downto 0);

signal last_trig_bits_latched : std_logic_vector(num_beams-1 downto 0);
signal trig_array_for_scalers : std_logic_vector(2*(num_beams+1) downto 0); --//on clk_data_i

signal internal_phased_trig_en : std_logic := '0'; --enable this trigger block from sw
signal internal_trigger_channel_mask : std_logic_vector(7 downto 0);
signal internal_trigger_beam_mask : std_logic_vector(num_beams-1 downto 0);

signal bits_for_trigger : std_logic_vector(num_beams-1 downto 0);
signal trig_array_for_scalars : std_logic_vector (2*(num_beams+1)-1 downto 0);
signal trig_bits_metadata: std_logic_vector(num_beams-1 downto 0);

--------------
--initialize components
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

--component power_lut is 
--port(
--		clk_i    : in std_logic;
--		a			: in	signed(6 downto 0);
--		z			: out	unsigned(13 downto 0));
--end component;


--------------

begin
------------------------------------------------

--process to shift thresholds from regs into the full power sizes
--can either be additive or can be set so 12 bits is assigned to the upper 12 bits
proc_convert_thresholds : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
			trig_beam_thresh(i)<=resize(input_trig_thresh(i),20)+threshold_offset;
			servo_beam_thresh(i)<=resize(input_servo_thresh(i),20)+threshold_offset;
		end loop;
			
	end if;
end process;


proc_pipeline_data : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then

		streaming_data(0,1)<=signed(ch0_data_i(15 downto 8))-baseline; --WHEN I PUT THIS ON REAL BEACON I WILL NEED TO MATCH THESE TO THE HPOL CHANS + BROKEN CHAN
		streaming_data(0,0)<=signed(ch0_data_i(7 downto 0))-baseline;
			
		streaming_data(1,1)<=signed(ch1_data_i(15 downto 8))-baseline;
		streaming_data(1,0)<=signed(ch1_data_i(7 downto 0))-baseline;
		
		streaming_data(2,1)<=signed(ch2_data_i(15 downto 8))-baseline;
		streaming_data(2,0)<=signed(ch2_data_i(7 downto 0))-baseline;
		
		streaming_data(3,1)<=signed(ch3_data_i(15 downto 8))-baseline;
		streaming_data(3,0)<=signed(ch3_data_i(7 downto 0))-baseline;

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

	if rising_edge(clk_data_i) and internal_phased_trig_en = '1' then
		--phase waveforms
		for i in 0 to num_beams-1 loop --loop over beams
			for j in 0 to phased_sum_length-1 loop
				phased_beam_waves_buff(i,j)<=resize(streaming_data(0,beam_delays(i,0)-(j-11)),10)
					+resize(streaming_data(1,beam_delays(i,1)+(j-7)),10)
					+resize(streaming_data(2,beam_delays(i,2)+(j-7)),10)
					+resize(streaming_data(3,beam_delays(i,3)+(j-7)),10)
					+resize(streaming_data(4,beam_delays(i,4)+(j-7)),10)
					+resize(streaming_data(5,beam_delays(i,5)+(j-7)),10);
					
				if(to_integer(phased_beam_waves_buff(i,j))>63) then
					phased_beam_waves(i,j)<=b"0111111";--saturate max
				elsif(to_integer(phased_beam_waves_buff(i,j))<-63) then
				  phased_beam_waves(i,j)<=b"1000000"; --saturate min
				else
					phased_beam_waves(i,j)<=resize(phased_beam_waves_buff(i,j),7); --this can be 10, 9 fits in a 1/4 of dsp. the rest of the calculations souldnt overflow
				end if;	

			end loop;
		end loop;

	end if;

end process;

--attempt at power LUT
--DO_POWER_BEAM : for i in 0 to num_beams-1 generate
--	DO_POWER_SAMPLE : for j in 0 to phased_sum_length-1 generate
--		xPOWERLUT : power_lut
--		port map(
--		clk_i => clk_data_i,
--		a				=> phased_beam_waves(i,j),
--		z				=> phased_power(i,j)(13 downto 0));
--	end generate;
--end generate;

------------------------------------------------
proc_do_beam_square : process(clk_data_i,rst_i)
begin

	if rising_edge(clk_data_i) then
   	for i in 0 to num_beams-1 loop
			for j in 0 to phased_sum_length-1 loop
				phased_power(i,j)<=unsigned(abs(phased_beam_waves(i,j)))*unsigned(abs(phased_beam_waves(i,j)));
			end loop;
		end loop;
	end if;
end process;
------------------------------------------------
		
proc_do_beam_sum : process(clk_data_i,rst_i)
begin		

	if rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
		
			--do each half of the calc
			power_sum0(i)<=resize(phased_power(i,0),num_power_bits)+resize(phased_power(i,1),num_power_bits)+resize(phased_power(i,2),num_power_bits)
				+resize(phased_power(i,3),num_power_bits)+resize(phased_power(i,4),num_power_bits)+resize(phased_power(i,5),num_power_bits)
				+resize(phased_power(i,6),num_power_bits)+resize(phased_power(i,7),num_power_bits);
			power_sum1(i)<=resize(phased_power(i,8),num_power_bits)
				+resize(phased_power(i,9),num_power_bits)+resize(phased_power(i,10),num_power_bits)+resize(phased_power(i,11),num_power_bits)
				+resize(phased_power(i,12),num_power_bits)+resize(phased_power(i,13),num_power_bits)+resize(phased_power(i,14),num_power_bits)
				+resize(phased_power(i,15),num_power_bits);
			
			--sum intermediate powers
			power_sum(i)<=power_sum0(i)+power_sum1(i);
			
			--divide
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
TRIG_THRESHOLDS : for i in 0 to num_beams-1 generate
	INDIV_TRIG_BITS : for j in 0 to input_power_thesh_bits-1 generate
		xTRIGTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+i)(j), --threshold from software
		SignalOut_clkB	=> input_trig_thresh(i)(j));
	end generate;
end generate;

SERVO_THRESHOLDS : for i in 0 to num_beams-1 generate
	INDIV_SERVO_BITS : for j in 0 to input_power_thesh_bits-1 generate
		xSERVOTHRESHSYNC : signal_sync
		port map(
		clkA				=> clk_i,
		clkB				=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+i)(j+12), --threshold from software
		SignalOut_clkB	=> input_servo_thresh(i)(j));
	end generate;
end generate;

------------
TRIGBEAMMASKA : for i in 0 to num_beams-1 generate --beam masks. 1 == on
--TRIGBEAMMASKA : for i in 0 to 23 generate --beam masks. 1 == on
	xTRIGBEAMMASKSYNC : signal_sync
	port map(
	clkA	=> clk_i,   clkB	=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base)))(i), --trig channel mask
	SignalOut_clkB	=> internal_trigger_beam_mask(i));
end generate;

--TRIGBEAMMASKB : for i in 0 to num_beams-1-24 generate --beam masks. 1 == on
--	xTRIGBEAMMASKSYNC : signal_sync
--	port map(
--	clkA	=> clk_i,   clkB	=> clk_data_i,
--	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base_extra)))(i), --trig channel mask
--	SignalOut_clkB	=> internal_trigger_beam_mask(i+24));
--end generate;
------------

----TRIGGER OUT!!
phased_trig_o <= phased_trigger_reg(0); --phased trigger for 0->1 transition. phased_trigger_reg(0) for absolute trigger 
--------------
trigscaler: flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> phased_trigger_reg(0),
		--in_clkA		=> phased_trigger,
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
		in_clkA		=> phased_servo_reg(0),
		--in_clkA		=> phased_servo,
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
	SignalIn_clkA	=> registers_i(to_integer(unsigned(trigger_enable_reg_adr)))(9), --overall phased trig enable bit
	SignalOut_clkB	=> internal_phased_trig_en);
end rtl;