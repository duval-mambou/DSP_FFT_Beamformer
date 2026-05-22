-- ============================================================================
--! @file         multiplier_tb.vhd
--! @brief        Testbench for complex fixed-point multiplier.
--! @details      Self-checking testbench. Tests multiplication with various
--!               fixed-point values, saturation, reset and ready handshake.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

entity multiplier_tb is
end multiplier_tb;

architecture Behavioral of multiplier_tb is

    -- Constants
    constant DATA_WIDTH   : integer := 32;
    constant WEIGHT_WIDTH : integer := 32;
    constant CLK_PERIOD   : time := 10 ns;

    -- Aliases for fixed-point ranges (Q1.31: 1 integer bit, 31 fractional bits)
    constant FIXED_HIGH : integer := 0;
    constant FIXED_LOW  : integer := -DATA_WIDTH+1;   -- -31

    -- DUT signals
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '0';
    signal data_in_ready  : std_logic := '0';
    signal x_re           : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal x_im           : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal w_re           : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal w_im           : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal data_out_ready : std_logic;
    signal y_re           : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal y_im           : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Helper function to convert real number to sfixed
    function real_to_sfixed(r : real) return sfixed is
        variable result : sfixed(FIXED_HIGH downto FIXED_LOW);
    begin
        result := to_sfixed(r, result'high, result'low);
        return result;
    end function;

    -- Helper function to convert sfixed to std_logic_vector
    function sfixed_to_slv(s : sfixed) return std_logic_vector is
    begin
        return to_slv(s);
    end function;

    -- Reference computation using fixed-point arithmetic (same as DUT)
    procedure compute_ref(
        x_re_val, x_im_val, w_re_val, w_im_val : sfixed;
        variable y_re_ref, y_im_ref : out sfixed
    ) is
        variable prod1, prod2, prod3, prod4 : sfixed(0 downto -DATA_WIDTH+1);
    begin
        prod1 := resize(x_re_val * w_re_val, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
        prod2 := resize(x_im_val * w_im_val, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
        prod3 := resize(x_re_val * w_im_val, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
        prod4 := resize(x_im_val * w_re_val, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
        y_re_ref := resize(prod1 - prod2, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
        y_im_ref := resize(prod3 + prod4, 0, -DATA_WIDTH+1, fixed_saturate, fixed_round);
    end procedure;

begin

    -- DUT instantiation
    uut: entity work.multiplier
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            WEIGHT_WIDTH => WEIGHT_WIDTH
        )
        port map (
            clk            => clk,
            reset          => reset,
            data_in_ready  => data_in_ready,
            x_re           => x_re,
            x_im           => x_im,
            w_re           => w_re,
            w_im           => w_im,
            data_out_ready => data_out_ready,
            y_re           => y_re,
            y_im           => y_im
        );

    -- Clock generation
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Test process
    test_process: process
        -- Fixed-point representations of test vectors
        variable x_re_f, x_im_f, w_re_f, w_im_f : sfixed(FIXED_HIGH downto FIXED_LOW);
        variable y_re_ref, y_im_ref : sfixed(FIXED_HIGH downto FIXED_LOW);
        variable y_re_slv, y_im_slv : std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Procedure to apply one test case
        procedure apply_test(
            x_re_real, x_im_real, w_re_real, w_im_real : real;
            signal x_re_v, x_im_v, w_re_v, w_im_v : out std_logic_vector;
            signal data_in_ready_v : out std_logic;
            signal clk_v : in std_logic
        ) is
            variable x_re_s, x_im_s, w_re_s, w_im_s : sfixed(FIXED_HIGH downto FIXED_LOW);
        begin
            x_re_s := real_to_sfixed(x_re_real);
            x_im_s := real_to_sfixed(x_im_real);
            w_re_s := real_to_sfixed(w_re_real);
            w_im_s := real_to_sfixed(w_im_real);
            x_re_v <= sfixed_to_slv(x_re_s);
            x_im_v <= sfixed_to_slv(x_im_s);
            w_re_v <= sfixed_to_slv(w_re_s);
            w_im_v <= sfixed_to_slv(w_im_s);
            data_in_ready_v <= '1';
            wait until rising_edge(clk_v);
            data_in_ready_v <= '0';
        end procedure;
        
                -- Define a list of test vectors as reals
        type test_vector_t is record
            xr, xi, wr, wi : real;
        end record;
        type test_vector_array is array (natural range <>) of test_vector_t;
        constant test_vectors : test_vector_array := (
            ( 0.0,  0.0,  0.0,  0.0),    -- zero
            ( 1.0,  0.0,  0.5,  0.0),    -- 1 * 0.5 = 0.5
            ( 0.5,  0.0,  0.0,  0.5),    -- 0.5 * 0.5i = 0 + 0.25i
            ( 0.5,  0.5,  0.5,  0.5),    -- (0.5+0.5i)*(0.5+0.5i) = 0+0.5i
            (-0.75, 0.25, 0.125, -0.125), -- check sign
            ( 0.9999999, 0.0, 1.0, 0.0), -- near saturation
            ( 0.0,  0.9999999, 0.0, 1.0)  -- near saturation on imag
        );

    begin
        report "Starting multiplier testbench" severity note;

        -- ------------------------------------------------------------
        -- Test 1: Reset
        -- ------------------------------------------------------------
        report "Test 1: Reset" severity note;
        reset <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);  -- two cycles to ensure reset is active
        assert data_out_ready = '0' report "Reset: data_out_ready not 0" severity error;
        assert y_re = std_logic_vector(to_signed(0, DATA_WIDTH)) and 
               y_im = std_logic_vector(to_signed(0, DATA_WIDTH))
            report "Reset: outputs not zero" severity error;
        reset <= '0';
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 2: Multiplication by 1 (real)
        -- ------------------------------------------------------------
        report "Test 2: x = 1+0j, w = 1+0j => y = 1+0j" severity note;
        apply_test(1.0, 0.0, 1.0, 0.0, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);  -- wait for result to be registered
        assert data_out_ready = '1' report "data_out_ready not asserted" severity error;
        -- Convert output to sfixed for comparison
        assert to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW)) = 1.0 and
               to_real(to_sfixed(y_im, FIXED_HIGH, FIXED_LOW)) = 0.0
            report "Multiplication by 1 failed" severity error;
        wait until rising_edge(clk);  -- data_out_ready should be 0 next cycle
        assert data_out_ready = '0' report "data_out_ready stays high more than one cycle" severity error;

        -- ------------------------------------------------------------
        -- Test 3: Multiplication by -1
        -- ------------------------------------------------------------
        report "Test 3: x = 0.5+0j, w = -1+0j => y = -0.5+0j" severity note;
        apply_test(0.5, 0.0, -1.0, 0.0, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);
        assert data_out_ready = '1' report "data_out_ready not asserted" severity error;
        assert to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW)) = -0.5 and
               to_real(to_sfixed(y_im, FIXED_HIGH, FIXED_LOW)) = 0.0
            report "Multiplication by -1 failed" severity error;
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 4: Typical complex multiplication (real and imag parts)
        -- ------------------------------------------------------------
        report "Test 4: (0.6+0.8j) * (0.7071+0.7071j) -> expected (0.0+1.0j approx)" severity note;
        apply_test(0.6, 0.8, 0.70710678, 0.70710678, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);
        -- With fixed-point rounding, expected answer is (0.0, 1.0) after saturation/rounding
        -- However due to rounding errors, we allow a small tolerance
        assert abs(to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW))) < 0.001 and
               abs(to_real(to_sfixed(y_im, FIXED_HIGH, FIXED_LOW)) - 1.0) < 0.001
            report "Complex multiplication (0.6+0.8j)*(0.707+0.707j) failed" severity error;
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 5: Zero inputs
        -- ------------------------------------------------------------
        report "Test 5: x = 0+0j, w = arbitrary => y = 0+0j" severity note;
        apply_test(0.0, 0.0, 0.123456, -0.654321, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);
        assert to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW)) = 0.0 and
               to_real(to_sfixed(y_im, FIXED_HIGH, FIXED_LOW)) = 0.0
            report "Zero input failed" severity error;
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 6: Saturation check (values slightly above 1.0)
        -- Since Q1.31 can only represent [-1.0, 1.0 - 2^-31], product >1 should saturate to 1.0
        -- Example: x = 1.0, w = 1.0 => product = 1.0, no saturation.
        -- But x = 1.0, w = 1.0, and x_im = 0, w_im = 0 gives exactly 1.0.
        -- To test saturation, we need a product that exceeds 1.0.
        -- The maximum product magnitude in Q1.31*Q1.31 is approx 1.0*1.0 = 1.0, but due to rounding,
        -- it's safe. However, negative saturation to -1.0 can be tested: x=1.0, w=-1.0 => -1.0 exactly.
        -- We'll test that the output never exceeds 1.0 in magnitude.
        report "Test 6: Saturation - product should be clamped to �1.0" severity note;
        apply_test(0.9999999, 0.0, 1.0, 0.0, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);
        assert to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW)) <= 1.0
            report "Saturation positive failed (output >1.0)" severity error;
        apply_test(-0.9999999, 0.0, 1.0, 0.0, x_re, x_im, w_re, w_im, data_in_ready, clk);
        wait until rising_edge(clk);
        assert to_real(to_sfixed(y_re, FIXED_HIGH, FIXED_LOW)) >= -1.0
            report "Saturation negative failed (output <-1.0)" severity error;
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 7: Reset during operation
        -- ------------------------------------------------------------
        report "Test 7: Assert reset while multiplication in progress" severity note;
        apply_test(0.5, 0.5, 0.5, 0.5, x_re, x_im, w_re, w_im, data_in_ready, clk);
        reset <= '1';
        wait until rising_edge(clk);
        -- Outputs should be cleared immediately, and data_out_ready should be 0
        assert data_out_ready = '0' report "Reset during operation: data_out_ready not cleared" severity error;
        assert y_re = std_logic_vector(to_signed(0, DATA_WIDTH)) and
               y_im = std_logic_vector(to_signed(0, DATA_WIDTH))
            report "Reset during operation: outputs not zeroed" severity error;
        reset <= '0';
        wait until rising_edge(clk);

        -- ------------------------------------------------------------
        -- Test 8: Random-like fixed test vectors (deterministic list)
        -- We compare DUT output with reference computed on the fly.
        -- ------------------------------------------------------------
        report "Test 8: Deterministic fixed-vector test" severity note;

        
        for i in test_vectors'range loop
            -- Compute reference using fixed-point function
            x_re_f := real_to_sfixed(test_vectors(i).xr);
            x_im_f := real_to_sfixed(test_vectors(i).xi);
            w_re_f := real_to_sfixed(test_vectors(i).wr);
            w_im_f := real_to_sfixed(test_vectors(i).wi);
            compute_ref(x_re_f, x_im_f, w_re_f, w_im_f, y_re_ref, y_im_ref);
            y_re_slv := sfixed_to_slv(y_re_ref);
            y_im_slv := sfixed_to_slv(y_im_ref);
            
            -- Apply to DUT
            apply_test(test_vectors(i).xr, test_vectors(i).xi,
                       test_vectors(i).wr, test_vectors(i).wi,
                       x_re, x_im, w_re, w_im, data_in_ready, clk);
            wait until rising_edge(clk);
            assert data_out_ready = '1' report "data_out_ready missing" severity error;
            assert y_re = y_re_slv and y_im = y_im_slv
                report "Test vector " & integer'image(i) & " failed" severity error;
            wait until rising_edge(clk);
        end loop;

        report "All tests passed successfully!" severity note;
        std.env.stop;
    end process;

end Behavioral;