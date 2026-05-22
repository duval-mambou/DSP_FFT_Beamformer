--------------------------------------------------------------------------------
--  \file      tb_fifo.vhd
--  \entity    tb_fifo
--  \brief     Testbench for fifo and fifo_module entities
--
--  \author    generated
--  \version   1.0
--  \date      06/04/2026
--
--------------------------------------------------------------------------------
--  \details
--  This testbench validates both fifo.vhd and fifo_module.vhd.
--
--  Test plan:
--    1. Reset behaviour
--    2. Single write then single read
--    3. Full fill then full drain (wrap-around)
--    4. Simultaneous read and write
--    5. full / empty flag timing
--    6. fifo_module with FIFO_DEPTH = 1 (register path + bypass)
--    7. Reset in the middle of an operation
--
--  Each test prints a PASS / FAIL message via report.
--  A final summary counts failures.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fifo is
end tb_fifo;

architecture sim of tb_fifo is

  --------------------------------------------------------------------------
  -- DUT generics
  --------------------------------------------------------------------------
  constant C_DATA_WIDTH : natural := 8;
  constant C_FIFO_DEPTH : integer := 4;   -- must be > 1 for the main FIFO DUT

  --------------------------------------------------------------------------
  -- Clock period
  --------------------------------------------------------------------------
  constant C_CLK_PERIOD : time := 10 ns;

  --------------------------------------------------------------------------
  -- Signals for the main FIFO DUT (fifo, DEPTH = 4)
  --------------------------------------------------------------------------
  signal clk   : std_logic := '0';
  signal rst  : std_logic := '1';
  signal wr_en : std_logic := '0';
  signal din   : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal full  : std_logic;
  signal rd_en : std_logic := '0';
  signal dout  : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal empty : std_logic;

  --------------------------------------------------------------------------
  -- Signals for the fifo_module DUT with DEPTH = 1
  --------------------------------------------------------------------------
  signal clk_m   : std_logic := '0';
  signal rst_m  : std_logic := '1';
  signal wr_en_m : std_logic := '0';
  signal din_m   : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal full_m  : std_logic;
  signal rd_en_m : std_logic := '0';
  signal dout_m  : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal empty_m : std_logic;

  --------------------------------------------------------------------------
  -- Test failure counter (shared across all tests)
  --------------------------------------------------------------------------
  shared variable v_FAIL_COUNT : integer := 0;

  --------------------------------------------------------------------------
  -- Helper : check a condition and report PASS / FAIL
  --------------------------------------------------------------------------
  procedure check(
    condition  : in boolean;
    test_name  : in string
  ) is
  begin
    if condition then
      report "[PASS] " & test_name severity note;
    else
      report "[FAIL] " & test_name severity error;
      v_FAIL_COUNT := v_FAIL_COUNT + 1;
    end if;
  end procedure;

  --------------------------------------------------------------------------
  -- Helper : single write into the main FIFO DUT
  --------------------------------------------------------------------------
  procedure write_fifo(
    signal clk_s   : in  std_logic;
    signal wr_en_s : out std_logic;
    signal din_s   : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
    constant data  : in  std_logic_vector(C_DATA_WIDTH-1 downto 0)
  ) is
  begin
    din_s   <= data;
    wr_en_s <= '1';
    wait until rising_edge(clk_s);
    wr_en_s <= '0';
  end procedure;

  --------------------------------------------------------------------------
  -- Helper : single read from the main FIFO DUT
  --------------------------------------------------------------------------
  procedure read_fifo(
    signal clk_s   : in  std_logic;
    signal rd_en_s : out std_logic
  ) is
  begin
    rd_en_s <= '1';
    wait until rising_edge(clk_s);
    rd_en_s <= '0';
  end procedure;

begin

  --------------------------------------------------------------------------
  -- Clock generation (main)
  --------------------------------------------------------------------------
  clk   <= not clk   after C_CLK_PERIOD / 2;
  clk_m <= not clk_m after C_CLK_PERIOD / 2;

  --------------------------------------------------------------------------
  -- DUT 1 : fifo (DEPTH = 4)
  --------------------------------------------------------------------------
  u_fifo : entity work.fifo
    generic map(
      DATA_WIDTH => C_DATA_WIDTH,
      FIFO_DEPTH => C_FIFO_DEPTH
    )
    port map(
      clk   => clk,
      rst  => rst,
      wr_en => wr_en,
      din   => din,
      full  => full,
      rd_en => rd_en,
      dout  => dout,
      empty => empty
    );

  --------------------------------------------------------------------------
  -- DUT 2 : fifo_module (DEPTH = 1, register path)
  --------------------------------------------------------------------------
  u_fifo_module : entity work.fifo_module
    generic map(
      DATA_WIDTH => C_DATA_WIDTH,
      FIFO_DEPTH => 1
    )
    port map(
      clk   => clk_m,
      rst  => rst_m,
      wr_en => wr_en_m,
      din   => din_m,
      full  => full_m,
      rd_en => rd_en_m,
      dout  => dout_m,
      empty => empty_m
    );

  --------------------------------------------------------------------------
  -- Main stimulus process
  --------------------------------------------------------------------------
  p_STIM : process

    -- local aliases for 8-bit test values
    constant D0 : std_logic_vector(C_DATA_WIDTH-1 downto 0) := x"AA";
    constant D1 : std_logic_vector(C_DATA_WIDTH-1 downto 0) := x"BB";
    constant D2 : std_logic_vector(C_DATA_WIDTH-1 downto 0) := x"CC";
    constant D3 : std_logic_vector(C_DATA_WIDTH-1 downto 0) := x"DD";

  begin

    -----------------------------------------------------------------------
    -- TEST 1 : Reset behaviour
    -----------------------------------------------------------------------
    report "=== TEST 1 : Reset ==================================" severity note;
    rst  <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    check(empty = '1', "T1 - empty asserted after reset");
    check(full  = '0', "T1 - full  de-asserted after reset");
    rst <= '0';
    wait until rising_edge(clk);

    -----------------------------------------------------------------------
    -- TEST 2 : Single write then single read
    -----------------------------------------------------------------------
    report "=== TEST 2 : Single write / read ====================" severity note;
    write_fifo(clk, wr_en, din, D0);
    wait for 1 ns;   -- let combinational signals settle
    check(empty = '0', "T2 - not empty after write");
    check(dout  = D0,  "T2 - dout correct before read");

    read_fifo(clk, rd_en);
    wait for 1 ns;
    check(empty = '1', "T2 - empty after reading last word");

    -----------------------------------------------------------------------
    -- TEST 3 : Full fill then full drain (wrap-around)
    -----------------------------------------------------------------------
    report "=== TEST 3 : Fill / drain + wrap-around =============" severity note;

    -- Fill all 4 slots
    write_fifo(clk, wr_en, din, D0);
    write_fifo(clk, wr_en, din, D1);
    write_fifo(clk, wr_en, din, D2);
    write_fifo(clk, wr_en, din, D3);
    wait for 1 ns;
    check(full  = '1', "T3 - full after writing 4 words");
    check(empty = '0', "T3 - not empty when full");

    -- Drain and verify data order (FIFO : D0 first out)
    check(dout = D0, "T3 - dout = D0 before first read");
    read_fifo(clk, rd_en); wait for 1 ns;
    check(dout = D1, "T3 - dout = D1 after 1st read");
    read_fifo(clk, rd_en); wait for 1 ns;
    check(dout = D2, "T3 - dout = D2 after 2nd read");
    read_fifo(clk, rd_en); wait for 1 ns;
    check(dout = D3, "T3 - dout = D3 after 3rd read");
    read_fifo(clk, rd_en); wait for 1 ns;
    check(empty = '1', "T3 - empty after draining all words");
    check(full  = '0', "T3 - full de-asserted after drain");

    -- Write again to verify pointer wrap-around works
    write_fifo(clk, wr_en, din, D2);
    wait for 1 ns;
    check(dout = D2, "T3 - wrap-around write/read OK");
    read_fifo(clk, rd_en);

    -----------------------------------------------------------------------
    -- TEST 4 : Simultaneous read and write (count must stay the same)
    -----------------------------------------------------------------------
    report "=== TEST 4 : Simultaneous read and write =============" severity note;

    -- Pre-load one word
    write_fifo(clk, wr_en, din, D0);
    wait for 1 ns;
    check(empty = '0', "T4 - not empty before simultaneous r/w");

    -- Simultaneous r/w : count must be stable, dout must become D1 next cycle
    din   <= D1;
    wr_en <= '1';
    rd_en <= '1';
    wait until rising_edge(clk);
    wr_en <= '0';
    rd_en <= '0';
    wait for 1 ns;
    check(empty = '0', "T4 - not empty after simultaneous r/w (1 word in)");
    -- Read out remaining word
    read_fifo(clk, rd_en); wait for 1 ns;
    check(empty = '1', "T4 - empty after reading last word");

    -----------------------------------------------------------------------
    -- TEST 5 : full / empty flag edge timing
    -----------------------------------------------------------------------
    report "=== TEST 5 : Flag edge timing ========================" severity note;

    -- empty must be '1' right now
    check(empty = '1', "T5 - empty before any write");
    check(full  = '0', "T5 - not full before any write");

    -- Write C_FIFO_DEPTH - 1 words : full must still be '0'
    write_fifo(clk, wr_en, din, D0);
    write_fifo(clk, wr_en, din, D1);
    write_fifo(clk, wr_en, din, D2);
    wait for 1 ns;
    check(full = '0', "T5 - not full with DEPTH-1 words");

    -- Write last word : full must assert
    write_fifo(clk, wr_en, din, D3);
    wait for 1 ns;
    check(full = '1', "T5 - full asserts on last write");

    -- Read one word : full must de-assert
    read_fifo(clk, rd_en); wait for 1 ns;
    check(full = '0', "T5 - full de-asserts after one read");

    -- Drain the rest
    read_fifo(clk, rd_en);
    read_fifo(clk, rd_en);
    read_fifo(clk, rd_en);
    wait for 1 ns;
    check(empty = '1', "T5 - empty after full drain");

    -----------------------------------------------------------------------
    -- TEST 6 : Reset in the middle of an operation
    -----------------------------------------------------------------------
    report "=== TEST 6 : Mid-operation reset ====================" severity note;

    write_fifo(clk, wr_en, din, D0);
    write_fifo(clk, wr_en, din, D1);
    wait for 1 ns;
    check(empty = '0', "T6 - not empty before reset");

    -- Apply reset
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    check(empty = '1', "T6 - empty after mid-operation reset");
    check(full  = '0', "T6 - not full after mid-operation reset");

    -----------------------------------------------------------------------
    -- TEST 7 : fifo_module DEPTH = 1 - register path
    -----------------------------------------------------------------------
    report "=== TEST 7 : fifo_module DEPTH=1 ====================" severity note;

    rst_m <= '1';
    wait until rising_edge(clk_m);
    rst_m <= '0';
    wait until rising_edge(clk_m);

    -- full and empty should always be '0' for DEPTH = 1 implementation
    check(full_m  = '0', "T7 - full always 0 (reg path)");
    check(empty_m = '0', "T7 - empty always 0 (reg path)");

    -- Write a value and read it back
    din_m   <= D0;
    wr_en_m <= '1';
    wait until rising_edge(clk_m);
    wr_en_m <= '0';
    wait for 1 ns;
    rd_en_m <= '1';
    check(dout_m = D0, "T7 - dout correct after write (reg path)");
    wait until rising_edge(clk_m);
    rd_en_m <= '0';

    -- Test bypass : simultaneous read/write ? dout must be din immediately
    din_m   <= D1;
    wr_en_m <= '1';
    rd_en_m <= '1';
    wait for 1 ns;   -- combinational bypass, no clock edge needed
    check(dout_m = D1, "T7 - bypass dout = din on simultaneous r/w");
    wait until rising_edge(clk_m);
    wr_en_m <= '0';
    rd_en_m <= '0';

    -----------------------------------------------------------------------
    -- Final summary
    -----------------------------------------------------------------------
    report "=====================================================" severity note;
    if v_FAIL_COUNT = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report "FAILURES DETECTED : " & integer'image(v_FAIL_COUNT) & " test(s) failed"
        severity error;
    end if;

    wait;  -- stop simulation
  end process p_STIM;

end sim;