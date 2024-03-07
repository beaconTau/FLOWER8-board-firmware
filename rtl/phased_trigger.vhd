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

type thresh_input is array (num_beams-1 downto 0) of unsigned(input_power_thesh_bits-1 downto 0);
signal input_trig_thresh : thresh_input;
signal input_servo_thresh : thresh_input;

--type streaming_data_array is array(7 downto 0) of std_logic_vector((streaming_buffer_length*8-1) downto 0);
--signal streaming_data : streaming_data_array := (others=>(others=>'0')); --pipeline data

type streaming_data_array is array(7 downto 0, streaming_buffer_length-1 downto 0) of signed(7 downto 0);
signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data


type phased_arr is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of signed(phased_sum_bits-1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves: phased_arr;

type square_waveform is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of unsigned(phased_sum_power_bits-1 downto 0);-- range 0 to 2**phased_sum_power_bits-1;--std_logic_vector(phased_sum_power_bits-1 downto 0);
signal phased_power : square_waveform;

type power_array is array (num_beams-1 downto 0) of unsigned(num_power_bits-1 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
signal trig_beam_thresh : power_array:=(others=>(others=>'0')) ; --trigger thresholds for all beams
signal servo_beam_thresh : power_array:=(others=>(others=>'0')) ;--(others=>(others=>'0')) --servo thresholds for all beams
signal power_sum : power_array; --power levels for all beams
signal avg_power: power_array;
--type beam_triggering is array (num_beams-1 downto 0) of std_logic;
--signal triggering_beam: beam_triggering := (others=>'0');
--signal servoing_beam: beam_triggering := (others=>'0');

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

constant num_div: integer := integer(log2(real(phased_sum_length)));
constant pad_zeros: std_logic_vector(num_div-1 downto 0):=(others=>'0');

signal coinc_window_int	: unsigned(7 downto 0) := x"02"; --//num of clk_data_i periods
constant baseline			: signed(7 downto 0) := x"80";

signal is_there_a_trigger: std_logic_vector(num_beams-1 downto 0);
signal is_there_a_servo: std_logic_vector(num_beams-1 downto 0);

signal internal_ramp:std_logic;
type fake_ramp_signal_t is array(1 downto 0) of signed(7 downto 0); 
signal fake_ramp_signal: fake_ramp_signal_t;
signal fake_ramp_count:signed(4 downto 0);
constant fake_factor:unsigned(3 downto 0):=b"0001";
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

proc_make_fake_data: process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		fake_ramp_count<=fake_ramp_count+1;
		fake_ramp_signal(1)<=b"000"&(fake_ramp_count+112);
		fake_ramp_signal(0)<=b"000"&((fake_ramp_count-1)+112);
	end if;
end process;

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
		if internal_ramp='1' then
			streaming_data(0,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(0,0)<=fake_ramp_signal(0)-baseline;
			
			streaming_data(1,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(1,0)<=fake_ramp_signal(0)-baseline;

			streaming_data(2,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(2,0)<=fake_ramp_signal(0)-baseline;
			

			streaming_data(3,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(3,0)<=fake_ramp_signal(0)-baseline;

			streaming_data(4,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(4,0)<=fake_ramp_signal(0)-baseline;
			
			streaming_data(5,1)<=fake_ramp_signal(1)-baseline;
			streaming_data(5,0)<=fake_ramp_signal(0)-baseline;
			
		else
			streaming_data(0,1)<=signed(ch0_data_i(15 downto 8))-baseline;
			streaming_data(0,0)<=signed(ch0_data_i(7 downto 0))-baseline;
			
			streaming_data(1,1)<=signed(ch1_data_i(15 downto 8))-baseline;
			streaming_data(1,0)<=signed(ch1_data_i(7 downto 0))-baseline;

			streaming_data(2,1)<=signed(ch2_data_i(15 downto 8))-baseline;
			streaming_data(2,0)<=signed(ch2_data_i(7 downto 0))-baseline;
			

			streaming_data(3,1)<=signed(ch3_data_i(15 downto 8))-baseline;
			streaming_data(3,0)<=signed(ch3_data_i(7 downto 0))-baseline;

			streaming_data(4,1)<=signed(ch4_data_i(15 downto 8))-baseline;
			streaming_data(4,0)<=signed(ch4_data_i(7 downto 0))-baseline;
			
			streaming_data(5,1)<=signed(ch5_data_i(15 downto 8))-baseline;
			streaming_data(5,0)<=signed(ch5_data_i(7 downto 0))-baseline;
		end if;
			
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

	if rst_i='1' or ENABLE_PHASED_TRIG='0' then
		--itshoulddosomethingbutidkwhatyet
		phased_beam_waves <= (others=>(others=>(others=>'0')));

	elsif rising_edge(clk_data_i) and internal_phased_trig_en = '0' then
		--itshoulddosomethingbutidkwhatyet
		phased_beam_waves <= (others=>(others=>(others=>'0')));
		
	elsif rising_edge(clk_data_i) then
		--phase waveforms
		for i in 0 to num_beams-1 loop --loop over beams
			for j in 0 to phased_sum_length-1 loop
				--phased_beam_waves(i*phased_sum_length+j) <= unsigned(streaming_data(0)(beam_delays(i*num_channels)+4 downto beam_delays(i*num_channels)-4)) 
				
				phased_beam_waves(i,j) <= (b"000"&streaming_data(0,beam_delays(i,0)-(j-3)))
					+streaming_data(1,beam_delays(i,1)-(j-3))
					+streaming_data(2,beam_delays(i,2)-(j-3))
					+streaming_data(3,beam_delays(i,3)-(j-3))
					+streaming_data(4,beam_delays(i,4)-(j-3))
					+streaming_data(5,beam_delays(i,5)-(j-3));					
					
			end loop;
		end loop;

	end if;

end process;
------------------------------------------------
proc_do_beam_square : process(clk_data_i,rst_i)
begin

	if rst_i = '1' then
		phased_power<=(others=>(others=>(others=>'0')));
	
	elsif rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
			for j in 0 to phased_sum_length-1 loop
				phased_power(i,j)<=unsigned(phased_beam_waves(i,j)*phased_beam_waves(i,j));
			end loop;
		end loop;
	
		end if;
end process;
------------------------------------------------
		
proc_do_beam_sum : process(clk_data_i,rst_i)
begin		

	if rst_i = '1' then
		power_sum<=(others=>(others=>'0'));
	elsif rising_edge(clk_data_i) then
		for i in 0 to num_beams-1 loop
				
			power_sum(i)<=(b"00"&phased_power(i,0))+phased_power(i,1)
				+phased_power(i,2)+phased_power(i,3)
				+phased_power(i,4)+phased_power(i,5);			
				
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
		
		trig_clear <= (others=>'0');
		trig_counter <= (others=>(others=>'0'));
		servo_clear <= (others=>'0');
		servo_counter <= (others=>(others=>'0'));

		
	elsif rising_edge(clk_data_i) then
		--loop over the beams and this is a big mess
		for i in 0 to num_beams-1 loop

			if trig_counter(i) = coinc_window_int then
				trig_clear(i) <= '1';
			else
				trig_clear(i) <= '0';
			end if;
				
			if beam_trigger_reg(i)(0) = '1'  then
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
				
			if beam_servo_reg(i)(0) = '1' then
				servo_counter(i) <= servo_counter(i) + 1;
			else
				servo_counter(i) <= (others=>'0');
			end if;
			------------------------------------
		
			if power_sum(i)>trig_beam_thresh(i) then
				triggering_beam(i)<='1';
				beam_trigger_reg(i)(0)<='1';
			else
				triggering_beam(i)<='0';
				beam_trigger_reg(i)(0)<='0';
			end if;
			if power_sum(i)>servo_beam_thresh(i) then
				servoing_beam(i)<='1';
				beam_servo_reg(i)(0)<='1';
			else
				servoing_beam(i)<='0';
				beam_servo_reg(i)(0)<='0';
			end if;
			last_trig_bits_latched_o(i)<=triggering_beam(i);
		
			--if triggering_beam(i) = internal_trigger_beam_mask(i) then
			--	phased_trigger_reg(0)<='1';
			--else 
			--	phased_trigger_reg(0)<='0';
			--end if;
			--f servoing_beam(i) = internal_trigger_beam_mask(i) then
			--	phased_servo_reg(0)<='1';
			--else 
			--	phased_servo_reg(0)<='0';
			--end if;
		end loop;
		
		is_there_a_trigger <= triggering_beam AND internal_trigger_beam_mask;
		is_there_a_servo <= servoing_beam AND internal_trigger_beam_mask;
		
		if to_integer(unsigned(is_there_a_trigger))>0 then
			phased_trigger_reg(0)<='1';
		else
			phased_trigger_reg(0)<='0';
		end if;
		if to_integer(unsigned(is_there_a_servo))>0 then
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

xRAMP_ENABLE : signal_sync
	port map(
	clkA	=> clk_i,   clkB	=> clk_data_i,
	SignalIn_clkA	=> registers_i(84)(0), --trig channel mask
	SignalOut_clkB	=>internal_ramp);

trig_array_for_scalars(2*num_beams+1 downto num_beams +2)<=servo_clear(num_beams-1 downto 0);
trig_array_for_scalars(num_beams+1)<=phased_servo;
trig_array_for_scalars(num_beams downto 1)<=trig_clear(num_beams-1 downto 0);
trig_array_for_scalars(0)<=phased_trigger;
	
----TRIGGER OUT!!
phased_trig_o <= phased_trigger_reg(0); --phased trigger for 0->1 transition. phased_trigger_reg(0) for absolute trigger 
--------------

TrigToScalers	:	 for i in 0 to 2*(num_beams+1)-1 generate 
	xTRIGSYNC : flag_sync
	port map(
		clkA 			=> clk_data_i,
		clkB			=> clk_i,
		in_clkA		=> trig_array_for_scalers(i),
		busy_clkA	=> open,
		out_clkB		=> trig_bits_o(i));
end generate TrigToScalers;
--------------
xTRIGENABLESYNC : signal_sync --phased trig enable bit
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(trigger_enable_reg_adr)))(9), --overall coinc trig enable bit
	SignalOut_clkB	=> internal_phased_trig_en);
end rtl;