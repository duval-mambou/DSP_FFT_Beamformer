-- ============================================================================
--! @file         tb_fifo_module.vhd
--! @brief        Testbench for fifo_module (corrected for pipelined read)
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fifo_module is
end tb_fifo_module;

architecture Behavioral of tb_fifo_module is
    constant DATA_WIDTH : natural := 32;
    constant CLK_PERIOD : time := 10 ns;

    signal clk_a    : std_logic := '0';
    signal rst_a    : std_logic := '1';
    signal wr_en_a  : std_logic := '0';
    signal din_a    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal full_a   : std_logic;
    signal rd_en_a  : std_logic := '0';
    signal dout_a   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal empty_a  : std_logic;

    signal clk_b    : std_logic := '0';
    signal rst_b    : std_logic := '1';
    signal wr_en_b  : std_logic := '0';
    signal din_b    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal full_b   : std_logic;
    signal rd_en_b  : std_logic := '0';
    signal dout_b   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal empty_b  : std_logic;

begin
    clk_a <= not clk_a after CLK_PERIOD/2;
    clk_b <= not clk_b after CLK_PERIOD/2;

    DUT_A : entity work.fifo_module
        generic map(DATA_WIDTH => DATA_WIDTH, FIFO_DEPTH => 1)
        port map(
            clk   => clk_a,
            srst  => rst_a,
            wr_en => wr_en_a,
            din   => din_a,
            full  => full_a,
            rd_en => rd_en_a,
            dout  => dout_a,
            empty => empty_a
        );

    DUT_B : entity work.fifo_module
        generic map(DATA_WIDTH => DATA_WIDTH, FIFO_DEPTH => 64)
        port map(
            clk   => clk_b,
            srst  => rst_b,
            wr_en => wr_en_b,
            din   => din_b,
            full  => full_b,
            rd_en => rd_en_b,
            dout  => dout_b,
            empty => empty_b
        );

    test_a : process
        variable p, f : integer := 0;
    begin
        rst_a <= '1'; wr_en_a <= '0'; rd_en_a <= '0';
        wait for 3 * CLK_PERIOD;
        rst_a <= '0';
        wait for CLK_PERIOD;

        -- Test A1 : simultaneous write/read (bypass)
        din_a <= std_logic_vector(to_unsigned(16#ADBEEF#, DATA_WIDTH));
        wr_en_a <= '1'; rd_en_a <= '1';
        wait for CLK_PERIOD;
        wr_en_a <= '0'; rd_en_a <= '0';
        wait for CLK_PERIOD;
        wait for 1 ns;
        if dout_a = std_logic_vector(to_unsigned(16#ADBEEF#, DATA_WIDTH)) then
            report "[PASS] FIFO_A1 : Bypass works" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_A1 : Bypass failed" severity error;
            f := f + 1;
        end if;

        -- A2 : sequential writes
        for val in 1 to 5 loop
            din_a <= std_logic_vector(to_unsigned(val * 100, DATA_WIDTH));
            wr_en_a <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en_a <= '0';
        wait for CLK_PERIOD;
        wait for 1 ns;
        if dout_a = std_logic_vector(to_unsigned(500, DATA_WIDTH)) then
            report "[PASS] FIFO_A2 : Last value stored correctly" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_A2 : Expected 500" severity error;
            f := f + 1;
        end if;

        -- A3 : flags
        wait for 1 ns;
        if full_a = '0' and empty_a = '0' then
            report "[PASS] FIFO_A3 : full=0, empty=0" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_A3 : flags not zero" severity error;
            f := f + 1;
        end if;

        -- A4 : reset (register unchanged)
        rst_a <= '1';
        wait for 2 * CLK_PERIOD;
        rst_a <= '0';
        wait for CLK_PERIOD;
        wait for 1 ns;
        if dout_a = std_logic_vector(to_unsigned(500, DATA_WIDTH)) then
            report "[PASS] FIFO_A4 : Register unchanged after reset" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_A4 : Register changed" severity error;
            f := f + 1;
        end if;

        report "================================================" severity note;
        report "BILAN FIFO depth=1 : PASS=" & integer'image(p) & " FAIL=" & integer'image(f) severity note;
        report "================================================" severity note;
        wait;
    end process;

    test_b : process
        variable p, f : integer := 0;
        variable got_val : integer;
    begin
        rst_b <= '1'; wr_en_b <= '0'; rd_en_b <= '0';
        wait for 3 * CLK_PERIOD;
        rst_b <= '0';
        wait for CLK_PERIOD;

        -- B1 : empty after reset
        wait for 1 ns;
        if empty_b = '1' then
            report "[PASS] FIFO_B1 : empty=1 after reset" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_B1 : empty should be 1" severity error;
            f := f + 1;
        end if;

        -- B2 : write 64 values -> full
        for i in 0 to 63 loop
            din_b <= std_logic_vector(to_unsigned(i, DATA_WIDTH));
            wr_en_b <= '1';
            rd_en_b <= '0';
            wait for CLK_PERIOD;
        end loop;
        wr_en_b <= '0';
        wait for 1 ns;
        if full_b = '1' then
            report "[PASS] FIFO_B2 : full=1 after 64 writes" severity note;
            p := p + 1;
        else
            report "[INFO] FIFO_B2 : full=" & std_logic'image(full_b) severity note;
        end if;

        -- B3 : read all 64 values (correct pipelined timing)
        for i in 0 to 63 loop
            rd_en_b <= '1';
            wait until rising_edge(clk_b);   -- active read for one cycle
            rd_en_b <= '0';
            -- After the rising edge, dout has the new value (read pointer updated)
            got_val := to_integer(unsigned(dout_b));
            if got_val /= i then
                report "[FAIL] FIFO_B3 slot=" & integer'image(i) &
                       " got=" & integer'image(got_val) & " exp=" & integer'image(i) severity error;
                f := f + 1;
            end if;
            -- Wait one more cycle before next read (optional, but keeps pace)
            wait until rising_edge(clk_b);
        end loop;

        if f = 0 then
            report "[PASS] FIFO_B3 : All 64 values read correctly" severity note;
            p := p + 1;
        end if;

        -- B4 : FIFO should be empty after reading all
        wait for 1 ns;
        if empty_b = '1' then
            report "[PASS] FIFO_B4 : empty=1 after full read" severity note;
            p := p + 1;
        else
            report "[FAIL] FIFO_B4 : FIFO not empty" severity error;
            f := f + 1;
        end if;

        -- B5 : simultaneous write/read
        -- Preload one value to avoid underflow
        din_b <= std_logic_vector(to_unsigned(0, DATA_WIDTH));
        wr_en_b <= '1';
        rd_en_b <= '0';
        wait for CLK_PERIOD;
        wr_en_b <= '0';
        for i in 0 to 31 loop
            din_b <= std_logic_vector(to_unsigned(i + 100, DATA_WIDTH));
            wr_en_b <= '1';
            rd_en_b <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en_b <= '0';
        rd_en_b <= '0';
        report "[PASS] FIFO_B5 : Simultaneous write/read completed" severity note;
        p := p + 1;

        report "================================================" severity note;
        report "BILAN FIFO depth=64 : PASS=" & integer'image(p) & " FAIL=" & integer'image(f) severity note;
        report "================================================" severity note;
        wait;
    end process;
end Behavioral;