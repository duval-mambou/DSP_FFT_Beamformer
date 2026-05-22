-- ============================================================================
--! @file         fifo_module.vhd
--! @brief        Wrapper module that implements a FIFO with configurable depth,
--!               using either a generic FIFO entity (depth > 1) or a simple
--!               register (depth = 1).
--! @details      This module provides a unified interface for FIFO depths of 1
--!               or more. For depth = 1, it uses a single register and provides
--!               a bypass path for simultaneous read and write. For depth > 1,
--!               it instantiates the full FIFO entity.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
--! @brief        FIFO module with depth of 1 or more.
--! @details      The module behaves as a standard FIFO. If FIFO_DEPTH > 1,
--!               it instantiates the generic FIFO entity. If FIFO_DEPTH = 1,
--!               it implements a single register with combinatorial bypass
--!               (when reading and writing at the same time, the output is
--!               the current input). The full and empty flags are tied to '0'
--!               in the depth=1 case because a single-register FIFO can never
--!               be full or empty in practice (the bypass makes it transparent).
--! @param[in]    DATA_WIDTH   Number of bits per word (default 14).
--! @param[in]    FIFO_DEPTH   Number of words the FIFO can hold (default 2).
--! @param[in]    srst         Synchronous reset (active high). Resets the FIFO.
--! @param[in]    clk          Clock signal. All operations are on rising edge.
--! @param[in]    wr_en        Write enable. When '1', din is written.
--! @param[in]    din          Input data bus (DATA_WIDTH bits wide).
--! @param[out]   full         Asserted when FIFO is full. For depth=1, always '0'.
--! @param[in]    rd_en        Read enable. When '1', data is presented on dout.
--! @param[out]   dout         Output data bus.
--! @param[out]   empty        Asserted when FIFO is empty. For depth=1, always '0'.
-- ============================================================================
entity fifo_module is
  generic (
    DATA_WIDTH : natural := 14;
    FIFO_DEPTH : integer := 2
  );
  port (
    srst  : in  std_logic;
    clk   : in  std_logic;

    -- Write interface
    wr_en : in  std_logic;
    din   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    full  : out std_logic;

    -- Read interface
    rd_en : in  std_logic;
    dout  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    empty : out std_logic
  );
end fifo_module;

-- ============================================================================
--! @brief        Architecture arch_fifo selects between full FIFO and register.
--! @details      Two generate blocks are used: one for FIFO_DEPTH > 1,
--!               another for FIFO_DEPTH = 1. When depth = 1, a single
--!               register stores the value on write, and the read output is
--!               either the newly written data (if simultaneous read/write)
--!               or the stored register value. Full and empty are forced to '0'.
-- ============================================================================
architecture arch_fifo of fifo_module is

  --! @brief        Register used when FIFO_DEPTH = 1.
  --! @details      Holds the single word when depth = 1. Initialized to zero.
  signal dreg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

begin

  -- ==========================================================================
  --! @brief        Generate block for FIFO depth greater than 1.
  --! @details      Instantiates the generic FIFO entity (fifo) with the same
  --!               generics and ports. This provides full circular buffer
  --!               behaviour.
  -- ==========================================================================
  gen_fifo : if FIFO_DEPTH > 1 generate

    u_fifo : entity work.fifo
      generic map(
        DATA_WIDTH => DATA_WIDTH,
        FIFO_DEPTH => FIFO_DEPTH
      )
      port map(
        clk   => clk,
        srst  => srst,
        din   => din,
        wr_en => wr_en,
        rd_en => rd_en,
        dout  => dout,
        full  => full,
        empty => empty
      );

  end generate;

  -- ==========================================================================
  --! @brief        Generate block for FIFO depth equal to 1.
  --! @details      Implements a simple register with bypass. When writing,
  --!               the input is stored in dreg. When reading, the output is
  --!               the stored value, except if a write occurs simultaneously,
  --!               in which case the output bypasses the register and directly
  --!               outputs the input data (this matches the behaviour of a
  --!               depth-1 FIFO with simultaneous read/write). Full and empty
  --!               are always '0' because the register is never considered
  --!               full or empty (it can always be written and read).
  -- ==========================================================================
  gen_reg : if FIFO_DEPTH = 1 generate

    --! @brief        Register storage process.
    --! @details      On rising clock edge, if write enable is asserted,
    --!               the input data is captured into dreg.
    process(clk)
    begin
      if rising_edge(clk) then
        if wr_en = '1' then
          dreg <= din;
        end if;
      end if;
    end process;

    --! @brief        Combinatorial output logic with bypass.
    --! @details      If both read and write are active in the same cycle,
    --!               output the new data directly (bypass). Otherwise,
    --!               output the stored register value.
    dout  <= din  when (rd_en = '1' and wr_en = '1') else dreg;
    --! @brief        Full flag is always '0' for depth=1 (never full).
    full  <= '0';
    --! @brief        Empty flag is always '0' for depth=1 (never empty).
    empty <= '0';

  end generate;

end arch_fifo;