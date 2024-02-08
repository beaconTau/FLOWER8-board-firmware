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
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity phased_trigger is
generic(
		ENABLE_PHASED_TRIG : std_logic := '1';
		--//trigger setting register: coinc trig enable is bit [8]
		trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
		--//base register for per-channel coincidence thresholds
		phased_trig_reg_base	: std_logic_vector(7 downto 0):= x"50"; --moved in FLOWER8
		phased_trig_param_reg	: std_logic_vector(7 downto 0):= x"55"; --moved in FLOWER8
		address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E" 
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
--Power 
type power_array is array (num_beams-1 downto 0) of unsigned(num_power_bits-1 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
signal trig_beam_thresh : power_array; --trigger thresholds for all beams
signal servo_beam_thresh : power_array; --servo thresholds for all beams
signal power_sum : power_array; --power levels for all beams

type square_waveform is array (phased_sum_length-1 downto 0,num_beams-1 downto 0) of unsigned(phased_sum_power_bits-1 downto 0);-- range 0 to 2**phased_sum_power_bits-1;--std_logic_vector(phased_sum_power_bits-1 downto 0);
signal phased_power : square_waveform;

type streaming_data_array is array(7 downto 0) of std_logic_vector((streaming_buffer_length*8-1) downto 0);

signal streaming_data : streaming_data_array := (others=>(others=>'0')); --pipeline data

type phased_arr is array (num_beams-1 downto 0,phased_sum_length-1 downto 0) of unsigned(phased_sum_bits-1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves: phased_arr;


type beam_triggering is array (num_beams-1 downto 0) of std_logic;
signal triggering_beam: beam_triggering := (others=>'0');
signal servoing_beam: beam_triggering := (others=>'0');


signal phased_trigger : std_logic;
signal phased_trigger_reg : std_logic_vector(1 downto 0);

signal phased_servo : std_logic;
signal phased_servo_reg : std_logic_vector(1 downto 0);

type trigger_counter is array (num_beams-1 downto 0) of std_logic_vector(15 downto 0);

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
signal trig_array_for_scalars : std_logic_vector (23 downto 0);

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
proc_pipeline_data : process(clk_data_i)
begin
	if rising_edge(clk_data_i) then
		streaming_data(0)(streaming_buffer_length*8-1 downto 0) <= streaming_data(0)((streaming_buffer_length-2)*8-1 downto 0) & ch0_data_i(15 downto 0); --there is only good data in the lower two bytes
		streaming_data(1)(streaming_buffer_length*8-1 downto 0) <= streaming_data(1)((streaming_buffer_length-2)*8-1 downto 0) & ch1_data_i(15 downto 0);
		streaming_data(2)(streaming_buffer_length*8-1 downto 0) <= streaming_data(2)((streaming_buffer_length-2)*8-1 downto 0) & ch2_data_i(15 downto 0);
		streaming_data(3)(streaming_buffer_length*8-1 downto 0) <= streaming_data(3)((streaming_buffer_length-2)*8-1 downto 0) & ch3_data_i(15 downto 0);
		streaming_data(4)(streaming_buffer_length*8-1 downto 0) <= streaming_data(4)((streaming_buffer_length-2)*8-1 downto 0) & ch4_data_i(15 downto 0); 
		streaming_data(5)(streaming_buffer_length*8-1 downto 0) <= streaming_data(5)((streaming_buffer_length-2)*8-1 downto 0) & ch5_data_i(15 downto 0);
		streaming_data(6)(streaming_buffer_length*8-1 downto 0) <= streaming_data(6)((streaming_buffer_length-2)*8-1 downto 0) & ch6_data_i(15 downto 0);
		streaming_data(7)(streaming_buffer_length*8-1 downto 0) <= streaming_data(7)((streaming_buffer_length-2)*8-1 downto 0) & ch7_data_i(15 downto 0);
		--second streaming array for pipelining
		--streaming_data_2(0) <= streaming_data(0);
		--streaming_data_2(1) <= streaming_data(1);
		--streaming_data_2(2) <= streaming_data(2);
		--streaming_data_2(3) <= streaming_data(3);
		--streaming_data_2(4) <= streaming_data(4);
		--streaming_data_2(6) <= streaming_data(6);
		--streaming_data_2(7) <= streaming_data(7); not sure if pipelining needed yet. prob is
		
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
				phased_beam_waves(i,j) <= resize(unsigned(streaming_data(0)(beam_delays(i,0)+4 downto beam_delays(i,0)-4)),11) 
					+unsigned(streaming_data(1)(beam_delays(i,1)+4 downto beam_delays(i,1)-4))
					+unsigned(streaming_data(2)(beam_delays(i,2)+4 downto beam_delays(i,2)-4))
					+unsigned(streaming_data(3)(beam_delays(i,3)+4 downto beam_delays(i,3)-4))
					+unsigned(streaming_data(4)(beam_delays(i,4)+4 downto beam_delays(i,4)-4))
					+unsigned(streaming_data(5)(beam_delays(i,5)+4 downto beam_delays(i,5)-4));
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
				phased_power(j,i)<=resize(phased_beam_waves(i,j)*phased_beam_waves(i,j),23);
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
			power_sum(i)<=resize(phased_power(0,i)+phased_power(1,i)
				+phased_power(2,i)+phased_power(3,i)
				+phased_power(4,i)+phased_power(5,i),24);
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
		--loop over the beams
		for i in 0 to num_beams-1 loop
				
			if power_sum(i)>trig_beam_thresh(i) then
				triggering_beam(i)<='1';
			end if;
			if power_sum(i)>servo_beam_thresh(i) then
				servoing_beam(i)<='1';
			end if;
			last_trig_bits_latched_o(i)<=triggering_beam(i);
		
			if triggering_beam(i) = internal_trigger_beam_mask(i) then
				phased_trigger_reg(0)<='1';
			else 
				phased_trigger_reg(0)<='0';
			end if;
			if servoing_beam(i) = internal_trigger_beam_mask(i) then
				phased_servo_reg(0)<='1';
			else 
				phased_servo_reg(0)<='0';
			end if;
		end loop;
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

INDIV_TRIG_BITS : for i in 0 to num_beams-1 generate
	xTRIGTHRESHSYNC : signal_sync
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base))+i)(0), --threshold from software
	SignalOut_clkB	=> trig_beam_thresh(i)(0));
end generate;

--------------

INDIV_SERVO_BITS : for i in 0 to num_beams-1 generate
	xSERVOTHRESHSYNC : signal_sync
	port map(
	clkA				=> clk_i,
	clkB				=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base))+i)(i+8), --threshold from software
	SignalOut_clkB	=> servo_beam_thresh(i)(0));
end generate;

--------------

------------
TRIGBEAMMASK : for i in 0 to num_beams-1 generate
	xTRIGBEAMMASKSYNC : signal_sync
		port map(
		clkA	=> clk_i,   clkB	=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(internal_trigger_beam_mask)))(i), --trig channel mask
		SignalOut_clkB	=> internal_trigger_beam_mask(i));
end generate;
------------


trig_array_for_scalars(2*num_beams+1 downto num_beams +2)<=servo_clear(num_beams-1 downto 0);
trig_array_for_scalars(num_beams+1)<=phased_servo;
trig_array_for_scalars(num_beams downto 1)<=trig_clear(num_beams-1 downto 0);
trig_array_for_scalars(0)<=phased_trigger;
	

----TRIGGER OUT!!
phased_trig_o <= phased_trigger_reg(0); --coincidence_trigger; 
--------------

TrigToScalers	:	 for i in 0 to 2*num_beams+2 generate
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
	SignalOut_clkB	=> internal_phased_trig_en);
end rtl;