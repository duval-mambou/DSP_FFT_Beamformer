-- ============================================================================
--! @file         fft_radix2_sdf.vhd
--! @brief        Top-level module for a radix-2 Single-Delay Feedback (SDF) FFT.
--! @details      This module implements a fully pipelined, streaming FFT
--!               processor using the SDF architecture. It instantiates
--!               NUMBER_OF_STAGES = log2(N_FFT) stages, each being an
--!               fft_stage entity. Data flows from stage to stage through
--!               internal signal arrays. The design supports arbitrary
--!               power-of-two FFT sizes.
--! @author      Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.math_pkg.all;

-- ============================================================================
--! @brief        Top-level FFT entity.
--! @details      The FFT processes a continuous stream of input samples.
--!               When x_ready is asserted, the complex sample (x_re, x_im)
--!               is accepted. After the pipeline latency, the transformed
--!               samples appear on the outputs with y_ready asserted.
--!               The output order is bit-reversed (standard for SDF).
--! @param[in]    N_FFT     FFT size (must be a power of two, default 128).
--! @param[in]    clk       Clock signal. All operations on rising edge.
--! @param[in]    reset     Synchronous reset (active high). Clears all stages.
--! @param[in]    x_ready   Input data valid. When '1', x_re and x_im are sampled.
--! @param[in]    x_re      Real part of input sample (32-bit signed fixed-point).
--! @param[in]    x_im      Imaginary part of input sample.
--! @param[out]   y_ready   Output data valid. Asserted when y_re and y_im are valid.
--! @param[out]   y_re      Real part of output sample (FFT result).
--! @param[out]   y_im      Imaginary part of output sample.
-- ============================================================================
entity fft_radix2_sdf is
    generic (
        N_FFT : integer := 128
    );
    port(
        clk     : in  std_logic;
        reset   : in  std_logic;
        x_ready : in  std_logic;
        x_re    : in  std_logic_vector(32-1 downto 0);
        x_im    : in  std_logic_vector(32-1 downto 0);
        y_ready : out std_logic;
        y_re    : out std_logic_vector(32-1 downto 0);
        y_im    : out std_logic_vector(32-1 downto 0)
    );
end fft_radix2_sdf;

-- ============================================================================
--! @brief        Architecture Behavioral connects all FFT stages.
--! @details      The number of stages is computed as clog2(N_FFT). Arrays of
--!               data and ready signals are used to chain stages together.
--!               Each stage is instantiated with its own generic parameters.
--!               The first stage receives the top-level inputs, and the last
--!               stage drives the top-level outputs.
-- ============================================================================
architecture Behavioral of fft_radix2_sdf is

    --! @brief        Fixed data width (32 bits) throughout the FFT.
    constant DATA_WIDTH       : integer := 32;
    --! @brief        Address width for twiddle ROM (32 bits, enough for any size).
    constant W_ADD_WIDTH      : integer := 32;
    --! @brief        Number of pipeline stages = log2(N_FFT).
    constant NUMBER_OF_STAGES : integer := clog2(N_FFT);

    --! @brief        Array type for storing real/imag data buses across stages.
    type data_arr  is array(0 to NUMBER_OF_STAGES) of std_logic_vector(DATA_WIDTH-1 downto 0);
    --! @brief        Array type for storing ready signals across stages.
    type ready_arr is array(0 to NUMBER_OF_STAGES) of std_logic;

    --! @brief        Real part signals for each stage (including input and output).
    signal x_re_sig    : data_arr;
    --! @brief        Imaginary part signals for each stage.
    signal x_im_sig    : data_arr;
    --! @brief        Ready/valid signals between stages.
    signal x_ready_sig : ready_arr;

begin

    -- ==========================================================================
    --! @brief        Connect top-level inputs to the first stage.
    -- ==========================================================================
    x_ready_sig(0) <= x_ready;
    x_re_sig(0)    <= x_re;
    x_im_sig(0)    <= x_im;

    -- ==========================================================================
    --! @brief        Generate all FFT processing stages.
    --! @details      For i from 0 to NUMBER_OF_STAGES-1, instantiate an fft_stage.
    --!               Stage i receives its inputs from the arrays at index i,
    --!               and drives the arrays at index i+1. This chains the stages.
    -- ==========================================================================
    gen_stages : for i in 0 to NUMBER_OF_STAGES-1 generate

        u_fft_stage : entity work.fft_stage
            generic map(
                DATA_WIDTH   => DATA_WIDTH,
                WEIGHT_WIDTH => DATA_WIDTH,
                N_FFT        => N_FFT,
                STAGE        => i,
                W_ADD_WIDTH  => W_ADD_WIDTH
            )
            port map(
                clk     => clk,
                reset   => reset,
                x_ready => x_ready_sig(i),
                x_re    => x_re_sig(i),
                x_im    => x_im_sig(i),
                y_ready => x_ready_sig(i+1),
                y_re    => x_re_sig(i+1),
                y_im    => x_im_sig(i+1)
            );

    end generate;

    -- ==========================================================================
    --! @brief        Connect the last stage outputs to top-level ports.
    -- ==========================================================================
    y_ready <= x_ready_sig(NUMBER_OF_STAGES);
    y_re    <= x_re_sig(NUMBER_OF_STAGES);
    y_im    <= x_im_sig(NUMBER_OF_STAGES);

end Behavioral;