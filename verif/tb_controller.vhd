-- ============================================================================
--! @file         controller_tb.vhd
--! @brief        Testbench for controller (FFT stage control unit)
--! @details      Deterministic testbench. Tests reset, IDLE?STATE0?STATE1
--!               transition, address generation, and final dump phase.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity controller_tb is
end controller_tb;

architecture Behavioral of controller_tb is

    -- Constants (matching the generics of the DUT)
    constant N_STAGE   : integer := 128;
    constant N_FFT     : integer := 128;
    constant ADD_WIDTH : integer := 6;

    -- Derived constant (visible in testbench for checking)
    constant N_COUNTER     : integer := 2 * N_FFT / N_STAGE;   -- = 2
    constant HALF_STAGE    : integer := N_STAGE / 2;           -- = 64
    constant MAX_COUNTER   : integer := HALF_STAGE - 1;        -- = 63

    -- Clock and reset
    signal clk           : std_logic := '0';
    signal reset         : std_logic := '0';
    signal data_in_ready : std_logic := '0';

    -- DUT outputs
    signal en_read_fifo  : std_logic;
    signal mode          : std_logic;
    signal add_w         : std_logic_vector(ADD_WIDTH-1 downto 0);

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Helper procedure: wait for a given number of rising clock edges
    procedure wait_cycles(signal clk : in std_logic; cycles : in integer) is
    begin
        for i in 1 to cycles loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    -- Helper procedure: apply data_in_ready for one clock cycle
    procedure pulse_ready(signal clk : in std_logic; signal ready : out std_logic) is
    begin
        ready <= '1';
        wait until rising_edge(clk);
        ready <= '0';
        wait until rising_edge(clk);  -- one cycle low between pulses
    end procedure;

begin

    -- DUT instantiation
    uut: entity work.controller
        generic map (
            N_STAGE   => N_STAGE,
            N_FFT     => N_FFT,
            ADD_WIDTH => ADD_WIDTH
        )
        port map (
            clk           => clk,
            reset         => reset,
            data_in_ready => data_in_ready,
            en_read_fifo  => en_read_fifo,
            mode          => mode,
            add_w         => add_w
        );

    -- Clock generator
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Main test sequence (deterministic, no random)
    test_process: process
        variable cycle_cnt : integer := 0;
    begin
        report "Starting controller testbench" severity note;

        -- ====================================================================
        -- Test 1: Reset behaviour
        -- ====================================================================
        report "Test 1: Reset" severity note;
        reset <= '1';
        wait_cycles(clk, 2);
        assert en_read_fifo = '0' report "Reset: en_read_fifo not 0" severity error;
        assert mode = '0' report "Reset: mode not 0" severity error;
        assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "Reset: add_w not 0" severity error;
        reset <= '0';
        wait_cycles(clk, 1);

        -- ====================================================================
        -- Test 2: IDLE ? STATE0 transition (first half-stage)
        -- ====================================================================
        report "Test 2: IDLE -> STATE0" severity note;
        -- Apply N_STAGE/2 data_in_ready pulses (64 pulses)
        for i in 0 to MAX_COUNTER loop
            data_in_ready <= '1';
            wait until rising_edge(clk);
            data_in_ready <= '0';
            wait until rising_edge(clk);   -- one idle cycle between pulses
        end loop;

        -- After the 64th pulse, the state should have moved to STATE0
        -- At the same cycle that counter reaches 63, the transition occurs.
        -- We need to check that on the next rising edge, mode='1' and en_read_fifo='1'
        wait until rising_edge(clk);
        assert mode = '1' report "IDLE->STATE0: mode not 1" severity error;
        assert en_read_fifo = '1' report "IDLE->STATE0: en_read_fifo not 1" severity error;
        assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "IDLE->STATE0: add_w not 0" severity error;
        report "IDLE->STATE0 transition OK" severity note;

        -- ====================================================================
        -- Test 3: STATE0 ? STATE1 transition (second half-stage)
        -- ====================================================================
        report "Test 3: STATE0 -> STATE1" severity note;
        -- Apply another 64 pulses. During STATE0, add_w stays 0.
        for i in 0 to MAX_COUNTER loop
            -- Check that during STATE0, add_w remains 0
            if i < MAX_COUNTER then
                assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
                    report "STATE0: add_w changed unexpectedly" severity error;
            end if;
            data_in_ready <= '1';
            wait until rising_edge(clk);
            data_in_ready <= '0';
            wait until rising_edge(clk);
        end loop;

        -- After the last pulse, we should be in STATE1 on the next cycle
        wait until rising_edge(clk);
        assert mode = '0' report "STATE0->STATE1: mode not 0" severity error;
        assert en_read_fifo = '1' report "STATE0->STATE1: en_read_fifo lost" severity error;
        -- add_w at start of STATE1 should be 0 (counter = 0)
        assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "STATE1: initial add_w not 0" severity error;
        report "STATE0->STATE1 transition OK" severity note;

        -- ====================================================================
        -- Test 4: Remaining address dump phase (since N_COUNTER=2, we are done)
        -- ====================================================================
        report "Test 4: Address dump phase (after groups completed)" severity note;

        -- At this point, counter0 = N_COUNTER, so we are in the else branch of STATE1.
        -- The FSM will output addresses from 0 to MAX_COUNTER (63) without requiring data_in_ready.
        -- Let's observe that add_w increments each clock cycle.
        for i in 0 to MAX_COUNTER loop
            -- Expected address value equals i (since counter starts at 0 and increments)
            assert add_w = std_logic_vector(to_unsigned(i, ADD_WIDTH))
                report "Address dump: add_w mismatch at step " & integer'image(i) severity error;
            wait until rising_edge(clk);
        end loop;

        -- After MAX_COUNTER+1 cycles (i reaches 63), the controller should go back to IDLE
        -- and clear en_read_fifo_reg (so en_read_fifo becomes 0).
        wait until rising_edge(clk);
        assert en_read_fifo = '0' report "After dump: en_read_fifo not 0" severity error;
        assert mode = '0' report "After dump: mode not 0" severity error;
        assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "After dump: add_w not reset to 0" severity error;

        report "Address dump phase completed, back to IDLE" severity note;

        -- ====================================================================
        -- Test 5: Full cycle with two groups (simulate a complete stage)
        -- ====================================================================
        report "Test 5: Complete stage (two groups, i.e., N_COUNTER=2)" severity note;

        -- Reset to start from clean state
        reset <= '1';
        wait_cycles(clk, 2);
        reset <= '0';
        wait_cycles(clk, 1);
        assert en_read_fifo = '0' and mode = '0' and add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "Post-reset state corrupted" severity error;

        -- Group 0, IDLE phase (64 pulses)
        for i in 0 to MAX_COUNTER loop
            data_in_ready <= '1';
            wait until rising_edge(clk);
            data_in_ready <= '0';
            wait until rising_edge(clk);
        end loop;
        wait until rising_edge(clk);
        assert mode = '1' and en_read_fifo = '1' report "After IDLE: mode or en_read_fifo wrong" severity error;

        -- Group 0, STATE0 phase (64 pulses)
        for i in 0 to MAX_COUNTER loop
            data_in_ready <= '1';
            wait until rising_edge(clk);
            data_in_ready <= '0';
            wait until rising_edge(clk);
            -- During STATE0, add_w = 0
            if i < MAX_COUNTER then
                assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
                    report "STATE0: add_w not 0" severity error;
            end if;
        end loop;
        wait until rising_edge(clk);
        assert mode = '0' report "After STATE0: mode should be 0 for STATE1" severity error;
        -- Beginning of STATE1 for group 0? Actually after the last pulse of STATE0,
        -- the FSM moves to STATE1, but because counter0 becomes 1 (< N_COUNTER=2),
        -- it will start processing with twiddle address incrementing.
        -- Let's check that during STATE1, addresses increment.
        -- We'll simulate the 64 pulses of STATE1 for group 0.
        for i in 0 to MAX_COUNTER loop
            data_in_ready <= '1';
            wait until rising_edge(clk);
            -- On the first cycle of STATE1, add_w should equal counter which starts at 0
            if i = 0 then
                assert add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
                    report "STATE1 first address not 0" severity error;
            else
                -- For subsequent cycles, add_w increments each cycle (as long as data_in_ready is high)
                -- Actually add_w is updated with the current counter value before increment, so
                -- at the start of cycle i, counter equals i (if no missed pulses). We'll check that.
                assert add_w = std_logic_vector(to_unsigned(i, ADD_WIDTH))
                    report "STATE1: address mismatch at cycle " & integer'image(i) severity error;
            end if;
            data_in_ready <= '0';
            wait until rising_edge(clk);
        end loop;

        -- After 64 pulses, we should transition back to STATE0 for the second group (counter0 becomes 2)
        wait until rising_edge(clk);
        assert mode = '1' report "After STATE1: mode should be 1 (next STATE0)" severity error;
        assert en_read_fifo = '1' report "en_read_fifo lost after STATE1" severity error;

        -- Now we are in STATE0 for group 1 (last group). At the end of this group,
        -- counter0 will become N_COUNTER and we will enter the address dump phase.
        -- We only need to apply the required number of pulses.
        for i in 0 to MAX_COUNTER loop
            data_in_ready <= '1';
            wait until rising_edge(clk);
            data_in_ready <= '0';
            wait until rising_edge(clk);
        end loop;

        -- After these pulses, the FSM should go to STATE1 and then immediately into dump.
        wait until rising_edge(clk);  -- entering STATE1, mode becomes '0'
        assert mode = '0' report "Should enter STATE1 before dump" severity error;

        -- Now dump phase: addresses increment without data_in_ready
        for i in 0 to MAX_COUNTER loop
            assert add_w = std_logic_vector(to_unsigned(i, ADD_WIDTH))
                report "Dump: add_w mismatch at step " & integer'image(i) severity error;
            wait until rising_edge(clk);
        end loop;

        -- After dump, back to IDLE
        wait until rising_edge(clk);
        assert en_read_fifo = '0' and mode = '0' and add_w = std_logic_vector(to_unsigned(0, ADD_WIDTH))
            report "Final state not IDLE" severity error;

        report "Complete stage simulation successful" severity note;
        report "All tests passed!" severity note;
        std.env.stop;
    end process;

end Behavioral;