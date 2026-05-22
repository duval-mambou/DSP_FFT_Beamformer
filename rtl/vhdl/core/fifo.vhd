-- ============================================================================
--! @file         fifo.vhd
--! @brief        Generic synchronous FIFO (First-In First-Out) with configurable
--!               data width and depth.
--! @details      Implements a circular buffer with separate read and write
--!               pointers. Uses a synchronous reset and provides full/empty
--!               flags. Includes simulation-only assertions to catch illegal
--!               accesses (write when full, read when empty).
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
--! @brief        FIFO entity with configurable depth and data width.
--! @details      The FIFO operates on a single clock (clk). All operations are
--!               synchronous to the rising edge. A synchronous reset (srst)
--!               clears the FIFO. The interface is split into write side
--!               (wr_en, din, full) and read side (rd_en, dout, empty).
--!               The FIFO depth can be 1 or greater; for depth=1 a simple
--!               register is used (but this entity implements the full FIFO
--!               behaviour for any depth >= 1).
--! @param[in]    DATA_WIDTH   Number of bits per word (default 14).
--! @param[in]    FIFO_DEPTH   Number of words the FIFO can hold (default 2).
--! @param[in]    srst         Synchronous reset (active high). Resets pointers
--!                            and internal count.
--! @param[in]    clk          Clock signal. All operations are on rising edge.
--! @param[in]    wr_en        Write enable. When '1' and FIFO not full, din is
--!                            written to the FIFO.
--! @param[in]    din          Input data bus (DATA_WIDTH bits wide).
--! @param[out]   full         Asserted when FIFO is completely full (FIFO_COUNT
--!                            equals FIFO_DEPTH). No write is allowed then.
--! @param[in]    rd_en        Read enable. When '1' and FIFO not empty, data
--!                            from the read pointer is presented on dout.
--! @param[out]   dout         Output data bus. Combinatorial read from current
--!                            read pointer.
--! @param[out]   empty        Asserted when FIFO is completely empty.
-- ============================================================================
entity fifo is
  generic (
    DATA_WIDTH : natural := 14;
    FIFO_DEPTH : integer := 2
  );
  port (
    srst  : in  std_logic;
    clk   : in  std_logic;

    -- FIFO Write Interface
    wr_en : in  std_logic;
    din   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    full  : out std_logic;

    -- FIFO Read Interface
    rd_en : in  std_logic;
    dout  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    empty : out std_logic
  );
end fifo;

-- ============================================================================
--! @brief        Architecture arch_fifo implements the FIFO behaviour using
--!               a circular buffer with separate write and read pointers.
--! @details      The internal memory is an array of std_logic_vector. Pointers
--!               are integer types with range 0..FIFO_DEPTH-1. The word count
--!               (r_FIFO_COUNT) tracks how many valid words are stored.
--!               Full and empty are derived combinatorially from the count.
--!               The process p_CONTROL updates all registers synchronously.
--!               Simulation-only assertions check for write-while-full and
--!               read-while-empty.
-- ============================================================================
architecture arch_fifo of fifo is

  --! @brief        Storage array for FIFO data.
  --! @details      Indexed from 0 to FIFO_DEPTH-1. Each entry holds one word.
  type t_FIFO_DATA is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
  signal r_FIFO_DATA : t_FIFO_DATA := (others => (others => '0'));

  --! @brief        Write pointer and read pointer for the circular buffer.
  --! @details      r_WR_INDEX points to the next location to be written.
  --!               r_RD_INDEX points to the next location to be read.
  --!               Both wrap around after reaching FIFO_DEPTH-1.
  signal r_WR_INDEX : integer range 0 to FIFO_DEPTH-1 := 0;
  signal r_RD_INDEX : integer range 0 to FIFO_DEPTH-1 := 0;

  --! @brief        Current number of stored words in FIFO.
  --! @details      Range is extended to -1 and FIFO_DEPTH+1 to safely handle
  --!               updates without overflow in intermediate logic.
  signal r_FIFO_COUNT : integer range -1 to FIFO_DEPTH+1 := 0;

  --! @brief        Internal full and empty flags (combinatorial).
  signal w_FULL  : std_logic;
  signal w_EMPTY : std_logic;

begin

  -- ==========================================================================
  --! @brief        Main synchronous control process.
  --! @details      On each rising clock edge, the process:
  --!               - Applies synchronous reset (clears count, resets pointers)
  --!               - Updates the word count based on wr_en and rd_en
  --!               - Conditionally increments write pointer (if writing and
  --!                 not full) with circular wrap
  --!               - Conditionally increments read pointer (if reading and
  --!                 not empty) with circular wrap
  --!               - Stores incoming data into the memory at the current write
  --!                 index when wr_en is asserted.
  --! @note         The order of updates is important: the count is updated
  --!               before the pointers, but this is safe because the new count
  --!               is used for flags only in the next cycle (registered).
  -- ==========================================================================
  p_CONTROL : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        -- Reset: empty FIFO, both pointers to 0, count 0
        r_FIFO_COUNT <= 0;
        r_WR_INDEX   <= 0;
        r_RD_INDEX   <= 0;

      else
        -- --------------------------------------------------------------------
        -- Update stored word count
        -- - Write only -> increment count
        -- - Read only  -> decrement count
        -- - Simultaneous write and read -> count unchanged
        -- --------------------------------------------------------------------
        if (wr_en = '1' and rd_en = '0') then
          r_FIFO_COUNT <= r_FIFO_COUNT + 1;
        elsif (wr_en = '0' and rd_en = '1') then
          r_FIFO_COUNT <= r_FIFO_COUNT - 1;
        end if;

        -- --------------------------------------------------------------------
        -- Update write pointer (only when writing and FIFO is not full)
        -- --------------------------------------------------------------------
        if (wr_en = '1' and w_FULL = '0') then
          if r_WR_INDEX = FIFO_DEPTH-1 then
            r_WR_INDEX <= 0;          -- wrap to beginning
          else
            r_WR_INDEX <= r_WR_INDEX + 1;
          end if;
        end if;

        -- --------------------------------------------------------------------
        -- Update read pointer (only when reading and FIFO is not empty)
        -- --------------------------------------------------------------------
        if (rd_en = '1' and w_EMPTY = '0') then
          if r_RD_INDEX = FIFO_DEPTH-1 then
            r_RD_INDEX <= 0;          -- wrap to beginning
          else
            r_RD_INDEX <= r_RD_INDEX + 1;
          end if;
        end if;

        -- --------------------------------------------------------------------
        -- Write data into memory at the current write index
        -- Note: we use the old r_WR_INDEX (before possible update) because
        -- the write happens in the same cycle as the pointer increment.
        -- This is correct for a standard FIFO.
        -- --------------------------------------------------------------------
        if wr_en = '1' then
          r_FIFO_DATA(r_WR_INDEX) <= din;
        end if;

      end if;
    end if;
  end process p_CONTROL;

  -- ==========================================================================
  --! @brief        Combinatorial read output.
  --! @details      Always outputs the data at the current read pointer.
  --!               When FIFO is empty, the output is undefined (old data).
  --! @note         Read pointer advances only on rd_en, so dout remains stable
  --!               until the next read.
  -- ==========================================================================
  dout <= r_FIFO_DATA(r_RD_INDEX);

  -- ==========================================================================
  --! @brief        Full and empty flag generation (combinatorial).
  --! @details      full = '1' when count equals depth; empty = '1' when count = 0.
  -- ==========================================================================
  w_FULL  <= '1' when r_FIFO_COUNT = FIFO_DEPTH else '0';
  w_EMPTY <= '1' when r_FIFO_COUNT = 0          else '0';

  full  <= w_FULL;
  empty <= w_EMPTY;

  -- ==========================================================================
  -- Simulation-only assertions to catch illegal FIFO operations.
  -- These checks are active only in simulation (synthesis translate_off/on).
  -- ==========================================================================
  -- synthesis translate_off

  --! @brief        Assertion process that verifies no write when full and no
  --!               read when empty.
  --! @details      If either violation occurs, the simulation stops with a
  --!               failure message.
  p_ASSERT : process(clk)
  begin
    if rising_edge(clk) then
      if wr_en = '1' and w_FULL = '1' then
        report "ASSERT FAILURE - MODULE_REGISTER_FIFO: FIFO IS FULL AND BEING WRITTEN"
          severity failure;
      end if;

      if rd_en = '1' and w_EMPTY = '1' then
        report "ASSERT FAILURE - MODULE_REGISTER_FIFO: FIFO IS EMPTY AND BEING READ"
          severity failure;
      end if;
    end if;
  end process p_ASSERT;

  -- synthesis translate_on

end arch_fifo;