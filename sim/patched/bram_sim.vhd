--------------------------------------------------------------
-- Simulation model of MiSTer's spram (src/fpga/core/astrocade/bram.vhd),
-- which wraps Intel's altsyncram. Same behaviour: the address is
-- registered on every clock, the output is not, a write shows its new
-- data at once, and q reads all ones while cs is low.
-- Used only by the GHDL/Verilator simulation, not by the real build.
--------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY spram IS
  generic (
    addr_width    : integer := 8;
    data_width    : integer := 8;
    mem_init_file : string := " ";
    mem_name      : string := "MEM"
  );
  PORT
  (
    clock   : in  STD_LOGIC;
    address : in  STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
    data    : in  STD_LOGIC_VECTOR (data_width-1 DOWNTO 0) := (others => '0');
    enable  : in  STD_LOGIC := '1';
    wren    : in  STD_LOGIC := '0';
    q       : out STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
    cs      : in  std_logic := '1'
  );
END spram;

ARCHITECTURE SIM OF spram IS
  type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
  signal mem : mem_t := (others => (others => '0'));
  signal q0  : std_logic_vector(data_width-1 downto 0) := (others => '0');
BEGIN
  q <= q0 when cs = '1' else (others => '1');

  process(clock)
  begin
    if rising_edge(clock) then
      if (wren and cs) = '1' then
        mem(to_integer(unsigned(address))) <= data;
        q0 <= data;
      else
        q0 <= mem(to_integer(unsigned(address)));
      end if;
    end if;
  end process;
END SIM;
