-- ============================================================================
--! @file         fft_stage.vhd
--! @brief        Single stage of a radix-2 Single-Delay Feedback (SDF) FFT.
--! @details      This module implements one pipeline stage of an SDF FFT.
--!               It contains:
--!               - A controller that manages FIFO read, butterfly mode,
--!                 and twiddle ROM address.
--!               - A butterfly unit that performs radix-2 butterfly operations.
--!               - Two FIFO modules (real and imaginary) that provide the
--!                 delayed path required by the SDF architecture.
--!               - A twiddle ROM that supplies complex coefficients.
--!               - A complex multiplier that applies the twiddle factor.
--!               The stage processes data sequentially and outputs results
--!               to the next stage.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
--! @brief        FFT stage entity.
--! @details      The stage is parameterized by data width, FFT size, stage
--!               index, and address width. The internal span N_STAGE is
--!               computed as N_FFT / 2^STAGE. The FIFO depth is N_STAGE/2.
--!               The controller uses N_STAGE and N_FFT to generate the correct
--!               sequencing. The twiddle ROM is pre-loaded with coefficients
--!               for this stage's span.
--! @param[in]    DATA_WIDTH     Data width for real/imaginary signals.
--! @param[in]    WEIGHT_WIDTH   Unused, kept for compatibility.
--! @param[in]    N_FFT          Total FFT size (power of two).
--! @param[in]    STAGE          Current stage index (0-based).
--! @param[in]    W_ADD_WIDTH    Bit width of twiddle ROM address.
--! @param[in]    clk            Clock signal.
--! @param[in]    reset          Synchronous reset (active high).
--! @param[in]    x_ready        Input data valid from previous stage.
--! @param[in]    x_re           Real part of input sample.
--! @param[in]    x_im           Imaginary part of input sample.
--! @param[out]   y_ready        Output data valid to next stage.
--! @param[out]   y_re           Real part of output sample.
--! @param[out]   y_im           Imaginary part of output sample.
-- ============================================================================
entity fft_stage is
    generic (
        DATA_WIDTH   : integer := 32;
        WEIGHT_WIDTH : integer := 32;
        N_FFT        : integer := 128;
        STAGE        : integer := 0;
        W_ADD_WIDTH  : integer := 32
    );
    port(
        clk     : in  std_logic;
        reset   : in  std_logic;
        x_ready : in  std_logic;
        x_re    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        x_im    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        y_ready : out std_logic;
        y_re    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        y_im    : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end fft_stage;

-- ============================================================================
--! @brief        Architecture Behavioral contains all submodules and connections.
--! @details      The stage is built around the SDF principle: a FIFO of length
--!               N_STAGE/2 delays one of the butterfly inputs. The controller
--!               alternates between filling the FIFO and processing butterflies.
--!               The butterfly outputs are:
--!               - y1 (delayed) ? written back to FIFO
--!               - y2 (current) ? multiplied by twiddle ? stage output
-- ============================================================================
architecture Behavioral of fft_stage is

    --! @brief        Number of points for this stage (span length).
    --! @details      Computed as N_FFT shifted right by STAGE bits.
    constant N_STAGE : integer := to_integer(shift_right(to_unsigned(N_FFT, 32), STAGE));

    --! @brief        Twiddle ROM address from controller.
    signal add_w    : std_logic_vector(W_ADD_WIDTH-1 downto 0);
    --! @brief        Butterfly mode: '1' = computation, '0' = routing.
    signal mode     : std_logic := '0';
    --! @brief        Read enable for the FIFO (from controller).
    signal x1_ready : std_logic := '0';

    --! @brief        Real part of delayed data (from FIFO).
    signal x1_re : std_logic_vector(DATA_WIDTH-1 downto 0);
    --! @brief        Imaginary part of delayed data.
    signal x1_im : std_logic_vector(DATA_WIDTH-1 downto 0);

    --! @brief        Butterfly signals: x2_ready is just x_ready.
    signal x2_ready : std_logic := '0';
    --! @brief        y1_ready flag from butterfly (for FIFO write).
    signal y1_ready : std_logic := '0';
    --! @brief        y1 real output (to be stored in FIFO).
    signal y1_re    : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');
    --! @brief        y1 imaginary output.
    signal y1_im    : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');
    --! @brief        y2_ready flag from butterfly (for multiplier).
    signal y2_ready : std_logic := '0';
    --! @brief        y2 real output (to be multiplied by twiddle).
    signal y2_re    : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');
    --! @brief        y2 imaginary output.
    signal y2_im    : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');

    --! @brief        Real twiddle factor from ROM.
    signal w_re : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');
    --! @brief        Imaginary twiddle factor.
    signal w_im : std_logic_vector(DATA_WIDTH-1 downto 0):= (others => '0');

    --! @brief        FIFO empty flag (used to gate reads).
    signal empty      : std_logic := '0';
    --! @brief        Internal read enable for FIFO.
    signal read_fifo  : std_logic := '0';
    --! @brief        FIFO full flag (used to gate writes).
    signal full       : std_logic := '0';
    --! @brief        Internal write enable for FIFO.
    signal write_fifo : std_logic := '0';

begin

    -- ==========================================================================
    --! @brief        Instantiate the controller.
    --! @details      Generates en_read_fifo (x1_ready), mode, and add_w.
    -- ==========================================================================
    u_controller : entity work.controller
        generic map(
            N_STAGE   => N_STAGE,
            N_FFT     => N_FFT,
            ADD_WIDTH => W_ADD_WIDTH
        )
        port map(
            clk           => clk,
            reset         => reset,
            data_in_ready => x_ready,
            en_read_fifo  => x1_ready,
            mode          => mode,
            add_w         => add_w
        );

    -- ==========================================================================
    --! @brief        Instantiate the butterfly.
    --! @details      Performs either routing (mode='0') or compute (mode='1').
    -- ==========================================================================
    u_butterfly : entity work.butterfly
        generic map(
            DATA_WIDTH => DATA_WIDTH
        )
        port map(
            clk      => clk,
            reset    => reset,
            mode     => mode,
            x1_ready => x1_ready,
            x2_ready => x2_ready,
            x1_re    => x1_re,
            x1_im    => x1_im,
            x2_re    => x_re,
            x2_im    => x_im,
            y1_ready => y1_ready,
            y2_ready => y2_ready,
            y1_re    => y1_re,
            y1_im    => y1_im,
            y2_re    => y2_re,
            y2_im    => y2_im
        );

    -- ==========================================================================
    --! @brief        FIFO delay line for the real part.
    --! @details      Depth = N_STAGE/2. Stores y1_re and outputs x1_re.
    -- ==========================================================================
    u_fifo_module_real : entity work.fifo_module
        generic map(
            DATA_WIDTH => DATA_WIDTH,
            FIFO_DEPTH => N_STAGE/2
        )
        port map(
            clk   => clk,
            srst  => reset,
            din   => y1_re,
            wr_en => write_fifo,
            rd_en => read_fifo,
            dout  => x1_re,
            full  => open,
            empty => open
        );

    -- ==========================================================================
    --! @brief        FIFO delay line for the imaginary part.
    --! @details      Same depth and control signals as the real FIFO.
    -- ==========================================================================
    u_fifo_module_imag : entity work.fifo_module
        generic map(
            DATA_WIDTH => DATA_WIDTH,
            FIFO_DEPTH => N_STAGE/2
        )
        port map(
            clk   => clk,
            srst  => reset,
            din   => y1_im,
            wr_en => write_fifo,
            rd_en => read_fifo,
            dout  => x1_im,
            full  => full,
            empty => empty
        );

    -- ==========================================================================
    --! @brief        Complex multiplier.
    --! @details      Multiplies y2 (from butterfly) by the twiddle factor.
    -- ==========================================================================
    u_multiplier : entity work.multiplier
        generic map(
            DATA_WIDTH => DATA_WIDTH
        )
        port map(
            clk            => clk,
            reset          => reset,
            data_in_ready  => y2_ready,
            x_re           => y2_re,
            x_im           => y2_im,
            w_re           => w_re,
            w_im           => w_im,
            data_out_ready => y_ready,
            y_re           => y_re,
            y_im           => y_im
        );

    -- ==========================================================================
    --! @brief        Twiddle ROM.
    --! @details      Stores N_STAGE/2 coefficients. Address from controller.
    -- ==========================================================================
    u_twidle_rom : entity work.twidle_rom
        generic map(
            ADDR_W  => W_ADD_WIDTH,
            DATA_W  => DATA_WIDTH,
            N_STAGE => N_STAGE
        )
        port map(
            addr_i       => add_w,
            twiddle_re_o => w_re,
            twiddle_im_o => w_im
        );

    -- ==========================================================================
    --! @brief        Local handshake signals.
    --! @details      x2_ready connects directly to input x_ready.
    --!               read_fifo is active only when controller requests read
    --!               (x1_ready) and FIFO is not empty.
    --!               write_fifo is active only when butterfly produces y1
    --!               (y1_ready) and FIFO is not full.
    -- ==========================================================================
    x2_ready   <= x_ready;
    read_fifo  <= x1_ready and not empty;
    write_fifo <= y1_ready and not full;

end Behavioral;