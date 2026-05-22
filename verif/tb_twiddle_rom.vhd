-- ============================================================================
--! @file         twiddle_rom_tb.vhd
--! @brief        Self-checking testbench for twidle_rom
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use IEEE.fixed_pkg.all;

entity twiddle_rom_tb is
end entity;

architecture tb of twiddle_rom_tb is

    ------------------------------------------------------------------------
    -- Parameters
    ------------------------------------------------------------------------
    constant ADDR_W  : natural := 6;
    constant DATA_W  : natural := 32;
    constant N_STAGE : natural := 128;

    constant FIXED_HIGH : integer := 0;
    constant FIXED_LOW  : integer := -DATA_W + 1;

    ------------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------------
    signal addr_i       : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
    signal twiddle_re_o : std_logic_vector(DATA_W-1 downto 0);
    signal twiddle_im_o : std_logic_vector(DATA_W-1 downto 0);

    ------------------------------------------------------------------------
    -- Helper functions
    ------------------------------------------------------------------------
    function real_to_slv(r : real) return std_logic_vector is
        variable fx : sfixed(FIXED_HIGH downto FIXED_LOW);
    begin
        fx := to_sfixed(r, FIXED_HIGH, FIXED_LOW);
        return to_slv(fx);
    end function;

    function slv_to_real(s : std_logic_vector) return real is
    begin
        return to_real(to_sfixed(s, FIXED_HIGH, FIXED_LOW));
    end function;

begin

    ------------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------------
    uut : entity work.twidle_rom
        generic map(
            ADDR_W  => ADDR_W,
            DATA_W  => DATA_W,
            N_STAGE => N_STAGE
        )
        port map(
            addr_i       => addr_i,
            twiddle_re_o => twiddle_re_o,
            twiddle_im_o => twiddle_im_o
        );

    ------------------------------------------------------------------------
    -- Test process
    ------------------------------------------------------------------------
    process
        variable expected_re : real;
        variable expected_im : real;
        variable angle       : real;
        variable tol : real := 0.0001;
    begin
        report "Starting twiddle ROM testbench" severity note;

        --------------------------------------------------------------------
        -- Test 1 : k = 0 => 1 + j0
        --------------------------------------------------------------------
        report "Test 1: address 0" severity note;
        addr_i <= std_logic_vector(to_unsigned(0, ADDR_W));
        wait for 10 ns;

        assert abs(slv_to_real(twiddle_re_o) - 1.0) < tol
            report "k=0 real failed" severity error;

        assert abs(slv_to_real(twiddle_im_o) - 0.0) < tol
            report "k=0 imag failed" severity error;

        --------------------------------------------------------------------
        -- Test 2 : k = N/4 => 0 - j1
        --------------------------------------------------------------------
        report "Test 2: address N/4" severity note;
        addr_i <= std_logic_vector(to_unsigned(N_STAGE/4, ADDR_W));
        wait for 10 ns;

        assert abs(slv_to_real(twiddle_re_o) - 0.0) < tol
            report "k=N/4 real failed" severity error;

        assert abs(slv_to_real(twiddle_im_o) + 1.0) < tol
            report "k=N/4 imag failed" severity error;

        --------------------------------------------------------------------
        -- Test 3 : multiple deterministic values
        --------------------------------------------------------------------
        report "Test 3: sweep several addresses" severity note;

        for k in 0 to 10 loop
            addr_i <= std_logic_vector(to_unsigned(k, ADDR_W));
            wait for 10 ns;

            angle := -2.0 * math_pi * real(k) / real(N_STAGE);
            expected_re := cos(angle);
            expected_im := sin(angle);

            assert abs(slv_to_real(twiddle_re_o) - expected_re) < tol
                report "Mismatch real at k=" & integer'image(k)
                severity error;

            assert abs(slv_to_real(twiddle_im_o) - expected_im) < tol
                report "Mismatch imag at k=" & integer'image(k)
                severity error;
        end loop;

        --------------------------------------------------------------------
        -- Test 4 : last valid address
        --------------------------------------------------------------------
        report "Test 4: last valid address" severity note;
        addr_i <= std_logic_vector(to_unsigned((N_STAGE/2)-1, ADDR_W));
        wait for 10 ns;

        angle := -2.0 * math_pi * real((N_STAGE/2)-1) / real(N_STAGE);
        expected_re := cos(angle);
        expected_im := sin(angle);

        assert abs(slv_to_real(twiddle_re_o) - expected_re) < tol
            report "Last address real failed" severity error;

        assert abs(slv_to_real(twiddle_im_o) - expected_im) < tol
            report "Last address imag failed" severity error;

        --------------------------------------------------------------------
        -- Test 5 : invalid address => zero output
        --------------------------------------------------------------------
        report "Test 5: invalid address" severity note;
        addr_i <= std_logic_vector(to_unsigned(N_STAGE/2 + 1, ADDR_W));
        wait for 10 ns;

        assert twiddle_re_o = std_logic_vector(to_unsigned(0, DATA_W))
    report "Invalid address real not zero" severity error;
            report "Invalid address real not zero" severity error;

assert twiddle_im_o = std_logic_vector(to_unsigned(0, DATA_W))
    report "Invalid address imag not zero" severity error;
            report "Invalid address imag not zero" severity error;

        --------------------------------------------------------------------
        report "All twiddle ROM tests passed!" severity note;
        std.env.stop;
        wait;
    end process;

end architecture;