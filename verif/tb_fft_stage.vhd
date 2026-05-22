-- ============================================================================
--! @file         fft_stage_tb.vhd
--! @brief        Testbench for fft_stage - tests only the top-level ports.
--! @details      Applies a known input sequence and checks the output
--!               against pre-computed reference values.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fft_stage_tb is
end fft_stage_tb;

architecture Behavioral of fft_stage_tb is

    -- Parameters (must match the DUT)
    constant DATA_WIDTH   : integer := 16;
    constant WEIGHT_WIDTH : integer := 16;
    constant N_FFT        : integer := 4;
    constant STAGE        : integer := 0;
    constant W_ADD_WIDTH  : integer := 2;   -- address width for twiddle ROM
    constant CLK_PERIOD   : time := 10 ns;

    -- DUT signals
    signal clk     : std_logic := '0';
    signal reset   : std_logic := '0';
    signal x_ready : std_logic := '0';
    signal x_re    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal x_im    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal y_ready : std_logic;
    signal y_re    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal y_im    : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Test data: real inputs, imag = 0
    type sample_array is array (0 to N_FFT-1) of integer;
    constant input_re : sample_array := (0, 1, 2, 3);
    constant input_im : sample_array := (0, 0, 0, 0);

    -- Expected outputs for stage 0 (computed offline)
    -- For N=4, radix-2 SDF stage0 outputs:
    --   y0 = (x0 + x2)/2 = (0+2)/2 = 1
    --   y1 = (x1 + x3)/2 = (1+3)/2 = 2
    --   y2 = (x0 - x2)/2 * 1 = (0-2)/2 = -1
    --   y3 = (x1 - x3)/2 * (-j) = (1-3)/2 * (-j) = (-1)*(-j) = j
    constant exp_re : sample_array := (1, 2, -1, 0);
    constant exp_im : sample_array := (0, 0,  0, 1);

    -- Clock generation
    procedure wait_cycles(cycles : integer) is
    begin
        for i in 1 to cycles loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    -- DUT instantiation
    uut: entity work.fft_stage
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            WEIGHT_WIDTH => WEIGHT_WIDTH,
            N_FFT        => N_FFT,
            STAGE        => STAGE,
            W_ADD_WIDTH  => W_ADD_WIDTH
        )
        port map (
            clk     => clk,
            reset   => reset,
            x_ready => x_ready,
            x_re    => x_re,
            x_im    => x_im,
            y_ready => y_ready,
            y_re    => y_re,
            y_im    => y_im
        );

    -- Clock generator
    clk <= not clk after CLK_PERIOD/2;

    -- Test process
    process
    begin
        report "Starting fft_stage testbench (N_FFT=4, STAGE=0)" severity note;

        -- Reset
        reset <= '1';
        wait_cycles(2);
        reset <= '0';
        wait_cycles(1);
        assert y_ready = '0' report "Reset: y_ready not cleared" severity error;

        -- Feed input samples (one per two cycles)
        for i in 0 to N_FFT-1 loop
            x_re <= std_logic_vector(to_signed(input_re(i), DATA_WIDTH));
            x_im <= std_logic_vector(to_signed(input_im(i), DATA_WIDTH));
            x_ready <= '1';
            wait_cycles(1);
            x_ready <= '0';
            wait_cycles(1);   -- idle between samples
        end loop;

        -- Collect outputs (they appear after pipeline latency)
        for i in 0 to N_FFT-1 loop
            -- Wait until output ready
            while y_ready = '0' loop
                wait_cycles(1);
            end loop;
            -- Check output value
            assert to_integer(signed(y_re)) = exp_re(i) and
                   to_integer(signed(y_im)) = exp_im(i)
                report "Output mismatch at index " & integer'image(i) &
                       ": expected (" & integer'image(exp_re(i)) & "," &
                       integer'image(exp_im(i)) & ") got (" &
                       integer'image(to_integer(signed(y_re))) & "," &
                       integer'image(to_integer(signed(y_im))) & ")" severity error;
            wait_cycles(1);
        end loop;

        -- Ensure y_ready goes low after last output
        wait_cycles(1);
        assert y_ready = '0' report "y_ready stuck high after all outputs" severity error;

        report "Simulation completed successfully" severity note;
        std.env.stop;
    end process;

end Behavioral;