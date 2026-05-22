-- ============================================================================
--! @file         fft128_radix2_sdf_tb.vhd
--! @brief        Testbench for the 128-point radix-2 SDF FFT processor.
--! @details      This testbench reads test vectors from a text file, applies
--!               them to the DUT (fft_radix2_sdf), and compares the outputs
--!               against expected results with a user-defined tolerance.
--!               It supports multiple test frames (N_TESTS = 12) and handles
--!               bit-reversal of output indices automatically.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

-- ============================================================================
--! @brief        Testbench entity.
--! @details      No ports; all signals are internal. Generics allow adjusting
--!               the clock period, FFT size, and input file name.
--! @param[in]    CLK_PERIOD  Clock period in ns (default 20).
--! @param[in]    N_FFT       FFT size (default 128).
--! @param[in]    INPUT_FILE  Name of the file containing test vectors.
-- ============================================================================
entity fft128_radix2_sdf_tb is
    generic(
        CLK_PERIOD : integer := 20;
        N_FFT      : integer := 128;
        INPUT_FILE : string := "fft128_testdata.txt"
    );
end fft128_radix2_sdf_tb;

-- ============================================================================
--! @brief        Architecture sim contains clock generation, stimulus, and checks.
--! @details      The testbench loads all test frames into internal arrays,
--!               then sequentially feeds each frame to the DUT, collects
--!               outputs, and compares them with the expected FFT results.
--!               Bit-reversal is applied to output indices because the
--!               SDF FFT produces results in bit-reversed order.
-- ============================================================================
architecture sim of fft128_radix2_sdf_tb is

    --! @brief        Number of test frames in the input file.
    constant N_TESTS    : integer := 12;
    --! @brief        Absolute tolerance for comparison (integer units).
    constant TOLERANCE  : integer := 20;

    --! @brief        Clock signal (initialized to '0').
    signal clk         : std_logic := '0';
    --! @brief        Reset signal (active high, initially asserted).
    signal rst         : std_logic := '1';
    --! @brief        Start / input valid flag for the DUT.
    signal start       : std_logic := '0';
    --! @brief        Real part of input sample.
    signal r_data_real : std_logic_vector(31 downto 0) := (others => '0');
    --! @brief        Imaginary part of input sample.
    signal r_data_img  : std_logic_vector(31 downto 0) := (others => '0');
    --! @brief        Real part of DUT output.
    signal y_data_real : std_logic_vector(31 downto 0);
    --! @brief        Imaginary part of DUT output.
    signal y_data_img  : std_logic_vector(31 downto 0);
    --! @brief        Output valid flag from DUT.
    signal finished    : std_logic;

    --! @brief        Type for a single frame of integer samples.
    type int_array_t   is array (0 to N_FFT-1) of integer;
    --! @brief        Type for all frames (N_TESTS frames).
    type frame_array_t is array (0 to N_TESTS-1) of int_array_t;

    --! @brief        Simulation end flag (stops clock generation).
    signal sim_done : boolean := false;

    --! @brief        Convert integer to 32-bit signed std_logic_vector.
    --! @param[in]    x   Integer value.
    --! @return       Corresponding std_logic_vector in signed representation.
    function int_to_slv32(x : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(x, 32));
    end function;

    --! @brief        Convert 32-bit signed std_logic_vector to integer.
    --! @param[in]    x   std_logic_vector (signed).
    --! @return       Integer value.
    function slv32_to_integer(x : std_logic_vector(31 downto 0)) return integer is
    begin
        return to_integer(signed(x));
    end function;

    --! @brief        Compute integer logarithm base 2.
    --! @param[in]    n   Positive integer (power of two).
    --! @return       log2(n).
    function log2_int(n : integer) return integer is
        variable v : integer := n;
        variable r : integer := 0;
    begin
        while v > 1 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;

    --! @brief        Bit-reverse an integer index.
    --! @param[in]    idx       Input index (0 � 2^n_bits-1).
    --! @param[in]    n_bits    Number of bits to reverse.
    --! @return       Bit-reversed index.
    function bit_reverse(idx : integer; n_bits : integer) return integer is
        variable x   : integer := idx;
        variable rev : integer := 0;
    begin
        for k in 0 to n_bits-1 loop
            rev := rev * 2 + (x mod 2);
            x   := x / 2;
        end loop;
        return rev;
    end function;

    --! @brief        Number of bits needed to address N_FFT samples.
    constant FFT_BITS : integer := log2_int(N_FFT);

begin

    -- ==========================================================================
    --! @brief        Instantiate the Device Under Test (DUT).
    -- ==========================================================================
    DUT: entity work.fft_radix2_sdf
    port map(
        clk     => clk,
        x_ready => start,
        y_ready => finished,
        reset   => rst,
        x_re    => r_data_real,
        x_im    => r_data_img,
        y_re    => y_data_real,
        y_im    => y_data_img
    );

    -- ==========================================================================
    --! @brief        Clock generation process.
    --! @details      Produces a clock with period CLK_PERIOD ns. Runs until
    --!               sim_done becomes true.
    -- ==========================================================================
    clk_process : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for (CLK_PERIOD * 1 ns) / 2;
            clk <= '1';
            wait for (CLK_PERIOD * 1 ns) / 2;
        end loop;
        wait;
    end process;

    -- ==========================================================================
    --! @brief        Main stimulus and verification process.
    --! @details      Loads test vectors from the file specified by INPUT_FILE.
    --!               For each test frame, it:
    --!               - Applies reset.
    --!               - Feeds N_FFT input samples.
    --!               - Collects N_FFT output samples.
    --!               - Compares each output (with bit-reversal) against the
    --!                 expected value, using TOLERANCE.
    --!               - Reports mismatches and final statistics.
    -- ==========================================================================
    stim_proc : process
        file infile : text;
        variable l                : line;
        variable v_test_id        : integer;
        variable v_sample_idx     : integer;
        variable v_xin_re         : integer;
        variable v_xin_im         : integer;
        variable v_xout_re        : integer;
        variable v_xout_im        : integer;

        variable out_idx          : integer;
        variable got_outputs      : integer;
        variable timeout_cycles   : integer;
        variable exp_idx          : integer;

        variable dut_re           : integer;
        variable dut_im           : integer;

        variable err_count        : integer := 0;
        variable total_count      : integer := 0;

        variable line_ok          : boolean;

        variable xin_re_mem  : frame_array_t;
        variable xin_im_mem  : frame_array_t;
        variable xout_re_mem : frame_array_t;
        variable xout_im_mem : frame_array_t;
    begin
        ----------------------------------------------------------------------
        -- Load all FFT test vectors from file into local memories
        --
        -- File format per line (space-separated):
        --   test_id sample_idx xin_re xin_im xout_re xout_im
        ----------------------------------------------------------------------
        file_open(infile, INPUT_FILE, read_mode);
        report "Loading FFT vectors from file: " & INPUT_FILE severity note;

        while not endfile(infile) loop
            readline(infile, l);

            read(l, v_test_id, line_ok);
            if not line_ok then
                report "Failed to read test_id from input file." severity failure;
            end if;

            read(l, v_sample_idx, line_ok);
            if not line_ok then
                report "Failed to read sample_index from input file." severity failure;
            end if;

            read(l, v_xin_re, line_ok);
            if not line_ok then
                report "Failed to read xin_re from input file." severity failure;
            end if;

            read(l, v_xin_im, line_ok);
            if not line_ok then
                report "Failed to read xin_im from input file." severity failure;
            end if;

            read(l, v_xout_re, line_ok);
            if not line_ok then
                report "Failed to read xout_re from input file." severity failure;
            end if;

            read(l, v_xout_im, line_ok);
            if not line_ok then
                report "Failed to read xout_im from input file." severity failure;
            end if;

            if (v_test_id < 0) or (v_test_id >= N_TESTS) then
                report "Invalid test_id in file: " & integer'image(v_test_id) severity failure;
            end if;

            if (v_sample_idx < 0) or (v_sample_idx >= N_FFT) then
                report "Invalid sample_index in file: " & integer'image(v_sample_idx) severity failure;
            end if;

            xin_re_mem(v_test_id)(v_sample_idx)  := v_xin_re;
            xin_im_mem(v_test_id)(v_sample_idx)  := v_xin_im;
            xout_re_mem(v_test_id)(v_sample_idx) := v_xout_re;
            xout_im_mem(v_test_id)(v_sample_idx) := v_xout_im;
        end loop;

        file_close(infile);
        report "Finished loading FFT vectors." severity note;

        ----------------------------------------------------------------------
        -- Apply reset and initialize all DUT inputs
        ----------------------------------------------------------------------
        rst         <= '1';
        start       <= '0';
        r_data_real <= (others => '0');
        r_data_img  <= (others => '0');

        wait for 5 ns * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        ----------------------------------------------------------------------
        -- Execute all FFT test frames
        ----------------------------------------------------------------------
        for t in 0 to N_TESTS-1 loop
            report "--------------------------------------------------" severity note;
            report "Starting FFT test " & integer'image(t) severity note;

            ------------------------------------------------------------------
            -- Feed one complete frame of N_FFT complex input samples
            ------------------------------------------------------------------
            for i in 0 to N_FFT-1 loop
                wait until rising_edge(clk);
                start       <= '1';
                r_data_real <= int_to_slv32(xin_re_mem(t)(i));
                r_data_img  <= int_to_slv32(xin_im_mem(t)(i));
            end loop;

            wait until rising_edge(clk);
            start       <= '0';
            r_data_real <= (others => '0');
            r_data_img  <= (others => '0');

            ------------------------------------------------------------------
            -- Collect DUT outputs and compare with expected FFT reference
            ------------------------------------------------------------------
            out_idx        := 0;
            got_outputs    := 0;
            timeout_cycles := 0;

            while got_outputs < N_FFT loop
                wait until rising_edge(clk);
                timeout_cycles := timeout_cycles + 1;

                if finished = '1' then
                    dut_re := slv32_to_integer(y_data_real);
                    dut_im := slv32_to_integer(y_data_img);

                    -- FFT outputs are expected in bit-reversed order
                    exp_idx := bit_reverse(out_idx, FFT_BITS);

                    total_count := total_count + 1;

                    if abs(dut_re - xout_re_mem(t)(exp_idx)) > TOLERANCE or
                       abs(dut_im - xout_im_mem(t)(exp_idx)) > TOLERANCE then
                        err_count := err_count + 1;

                        report "Mismatch in test " & integer'image(t) &
                               ", output sample " & integer'image(out_idx) &
                               " (expected index " & integer'image(exp_idx) & ")" &
                               " | DUT_RE=" & integer'image(dut_re) &
                               " EXP_RE=" & integer'image(xout_re_mem(t)(exp_idx)) &
                               " | DUT_IM=" & integer'image(dut_im) &
                               " EXP_IM=" & integer'image(xout_im_mem(t)(exp_idx))
                               severity error;
                    end if;

                    out_idx     := out_idx + 1;
                    got_outputs := got_outputs + 1;
                end if;

                if timeout_cycles > 20000 then
                    report "Timeout waiting for FFT outputs in test " &
                           integer'image(t) severity failure;
                end if;
            end loop;

            report "Finished FFT test " & integer'image(t) severity note;

            ------------------------------------------------------------------
            -- Idle cycles between test frames
            ------------------------------------------------------------------
            for i in 0 to 5 loop
                wait until rising_edge(clk);
            end loop;
        end loop;

        ----------------------------------------------------------------------
        -- Final verification summary
        ----------------------------------------------------------------------
        report "==================================================" severity note;
        report "FFT verification finished." severity note;
        report "Total compared samples = " & integer'image(total_count) severity note;
        report "Total mismatches       = " & integer'image(err_count) severity note;

        if err_count = 0 then
            report "ALL TESTS PASSED." severity note;
        else
            report "TEST FAILED." severity failure;
        end if;

        sim_done <= true;
        wait;
    end process;

end sim;