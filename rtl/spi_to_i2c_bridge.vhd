---------------------------------------------------------------------------------
-- Univ. of Chicago  
--    --KICP--
--
-- PROJECT:      FLOWER
-- FILE:         spi_to_i2c_bridge.vhd
-- AUTHOR:       e.oberla
-- EMAIL         ejo@uchicago.edu
-- DATE:         1/2021
--
-- DESCRIPTION:  programming the Si5338 is hard..so this block allows direct control
--               of the i2c bus from the Beaglebone spi link.
--
--
--					 use register x7B to send i2c message
--              use register x7C to read register defined in bits [6..0]. data popped out on the system read register
---------------------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity spi_to_i2c_bridge is
	Port(
		reset_i			:  in		std_logic; --//active-hi reset
		clk_i				:	in		std_logic; --//10MHz on-board clock
		registers_i 	:	in 	register_array_type;
		address_i		:	in 	std_logic_vector(define_address_size-1 downto 0);
		i2c_read_o		:	out	std_logic_vector(23 downto 0); --//readout reg, merge to spi
		sda_io       	:  inout std_logic;                    --serial data output of i2c bus
		scl_io	      :  inout std_logic);  

end spi_to_i2c_bridge;

architecture rtl of spi_to_i2c_bridge is 

TYPE machine IS(idle, i2c_write_command, i2c_write, read_data); --needed states
  SIGNAL state       : machine;                       --state machine
  SIGNAL i2c_ena     : STD_LOGIC;                     --i2c enable signal
  SIGNAL i2c_addr    : STD_LOGIC_VECTOR(6 DOWNTO 0);  --i2c address signal
  SIGNAL i2c_rw      : STD_LOGIC;                     --i2c read/write command signal
  SIGNAL i2c_data_wr : STD_LOGIC_VECTOR(7 DOWNTO 0);  --i2c write data
  SIGNAL i2c_data_rd : STD_LOGIC_VECTOR(7 DOWNTO 0);  --i2c read data
  SIGNAL i2c_busy    : STD_LOGIC;                     --i2c busy signal
  SIGNAL busy_prev   : STD_LOGIC;                     --previous value of i2c busy signal
  
  SIGNAL read_buffer : STD_LOGIC_VECTOR(15 DOWNTO 0); --i2c read buffer, to system register space
  SIGNAL write_buffer: STD_LOGIC_VECTOR(15 DOWNTO 0); --i2c write buffer, from system register space
  
  CONSTANT adr_write : std_logic_vector(7 downto 0) := x"7C";
  CONSTANT adr_read	: std_logic_vector(7 downto 0) := x"7B";
  CONSTANT pll_hw_adr : std_logic_vector(6 downto 0) := "1110000"; --7-bit address = 0x70
  
begin


PROCESS(clk_i, reset_i)
    VARIABLE busy_cnt : INTEGER RANGE 0 TO 2 := 0;               --counts the busy signal transistions during one transaction
  BEGIN
    IF(reset_i = '1') THEN               --reset activated
      i2c_ena <= '0';                      --clear i2c enable
      busy_cnt := 0;                       --clear busy counter
		read_buffer <= (others=>'0');
		write_buffer <= (others=>'0');
		i2c_read_o <= (others=>'0');
      state <= idle;                      --return to start state

    ELSIF rising_edge(clk_i) THEN  			--rising edge of system clock
		
		i2c_read_o <= x"00" & read_buffer;
	 
      CASE state IS                        --state machine
         --idling.. 
		  WHEN idle =>
		  	--read_adr <= read_adr;
			--write_buffer <= write_buffer;
			IF address_i = adr_write THEN
				write_buffer <= registers_i(to_integer(unsigned(adr_write)))(15 downto 0); --inferred latch, fix  
				case registers_i(to_integer(unsigned(adr_write)))(16) is
					WHEN '0' =>     
						state <= i2c_write_command;
					WHEN '1' =>
						state <= i2c_write;
				END CASE;
			ELSIF address_i = adr_read THEN
				state <= read_data;
			ELSE
				state <= idle;
			END IF;
					
        --i2c write 2 bytes
        WHEN i2c_write_command =>    
          busy_prev <= i2c_busy;                       --capture the value of the previous i2c busy signal
          IF(busy_prev = '0' AND i2c_busy = '1') THEN  --i2c busy just went high
            busy_cnt := busy_cnt + 1;                    --counts the times busy has gone from low to high during transaction
          END IF;
          CASE busy_cnt IS                             --busy_cnt keeps track of which command we are on
            WHEN 0 =>                                    --no command latched in yet
              i2c_ena <= '1';                              --initiate the transaction
              i2c_addr <= pll_hw_adr;     				--set the address of the temp chip
              i2c_rw <= '0';                               --command 1 is a write
              i2c_data_wr <= write_buffer(15 downto 8);     --internal register address          
            WHEN 1 =>                                    --1st busy high: command 1 latched, okay to issue command 2
              i2c_data_wr <= write_buffer(7 downto 0);   --internal command
            WHEN 2 =>                                    --2nd busy high: command 2 latched
              i2c_ena <= '0';                              --deassert enable to stop transaction after command 2
              IF(i2c_busy = '0') THEN                      --transaction complete
                busy_cnt := 0;                               --reset busy_cnt for next transaction
                state <= idle;                    
              END IF;
            WHEN OTHERS => NULL;
          END CASE;
			 
			--i2c write 1 byte [i.e. to set the internal address of the read address]
        WHEN i2c_write =>    
          busy_prev <= i2c_busy;                       --capture the value of the previous i2c busy signal
          IF(busy_prev = '0' AND i2c_busy = '1') THEN  --i2c busy just went high
            busy_cnt := busy_cnt + 1;                    --counts the times busy has gone from low to high during transaction
          END IF;
          CASE busy_cnt IS                             --busy_cnt keeps track of which command we are on
            WHEN 0 =>                                    --no command latched in yet
              i2c_ena <= '1';                              --initiate the transaction
              i2c_addr <= pll_hw_adr;     				--set the address of the temp chip
              i2c_rw <= '0';                               --command 1 is a write
              i2c_data_wr <= write_buffer(15 downto 8);     --internal register address          
            WHEN 1 =>                                    --2nd busy high: command 2 latched
              i2c_ena <= '0';                              --deassert enable to stop transaction after command 2
              IF(i2c_busy = '0') THEN                      --transaction complete
                busy_cnt := 0;                               --reset busy_cnt for next transaction
                state <= idle;                    
              END IF;
            WHEN OTHERS => NULL;
          END CASE;
			 
			 --read  data
        WHEN read_data =>
          busy_prev <= i2c_busy;                       --capture the value of the previous i2c busy signal
          IF(busy_prev = '0' AND i2c_busy = '1') THEN  --i2c busy just went high
            busy_cnt := busy_cnt + 1;                    --counts the times busy has gone from low to high during transaction
          END IF;
          CASE busy_cnt IS                             --busy_cnt keeps track of which command we are on
            WHEN 0 =>                                    --no command latched in yet
              i2c_ena <= '1';                              --initiate the transaction
              i2c_addr <= pll_hw_adr;                --set the address 
              i2c_rw <= '1';                               --command 1 is a read
            WHEN 1 =>                                    --1st busy high: command 1 latched, okay to issue command 2
              IF(i2c_busy = '0') THEN                      --indicates data read in command 1 is ready
                read_buffer(7 DOWNTO 0) <= i2c_data_rd;       --retrieve MSB data from command 1
              END IF;
            WHEN 2 =>                                    --2nd busy high: command 2 latched
              i2c_ena <= '0';                              --deassert enable to stop transaction after command 2
              IF(i2c_busy = '0') THEN                      --indicates data read in command 2 is ready
                read_buffer(15 DOWNTO 8) <= i2c_data_rd;        --retrieve LSB data from command 2
                busy_cnt := 0;                               --reset busy_cnt for next transaction
                state <= idle;                      
              END IF;
           WHEN OTHERS => NULL;
          END CASE;
		 
			--default to idle state
        WHEN OTHERS =>
          state <= idle;
			 
      END CASE;
    END IF;
  END PROCESS;

	--///////////////////////////////////////
	-----------------------------------------
 xI2C_MASTER : entity work.i2c_master
   generic map(
    input_clk => 10_000_000, --input clock speed from user logic in Hz
    bus_clk   => 400_000)   --speed the i2c bus (scl) will run at in Hz
	port map(
	 clk       => clk_i,              --system clock
    reset_n   => not reset_i,        --active low reset
    ena       => i2c_ena,            --latch in command
    addr      => i2c_addr, 			--address of target slave
    rw        => i2c_rw,              --'0' is write, '1' is read
    data_wr   => i2c_data_wr,			--data to write to slave (8 bit chunks)
    busy      => i2c_busy,           --indicates transaction in progress
    data_rd   => i2c_data_rd, 		--data read from slave (8 bit chunks)
    ack_error => open,                   --flag if improper acknowledge from slave
    sda       => sda_io,                   --serial data output of i2c bus
    scl       => scl_io);                  --serial clock output of i2c b
	--///////////////////////////////////////	

end rtl;