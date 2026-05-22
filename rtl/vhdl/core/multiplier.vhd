-- ============================================================================
--! @file         multiplier.vhd
--! @brief        Complex fixed-point multiplier with pipeline register.
--! @details      This module performs a complex multiplication:
--!               y = x * w, where x = x_re + j*x_im, w = w_re + j*w_im.
--!               The computation uses the fixed-point package (ieee.fixed_pkg)
--!               and includes saturation and rounding. Input and output are
--!               32-bit signed vectors representing Q1.31 fixed-point numbers.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

-- ============================================================================
--! @brief        Complex multiplier entity.
--! @details      Multiplies two complex numbers using four real multiplications.
--!               The formula is:
--!               - y_re = x_re * w_re - x_im * w_im
--!               - y_im = x_re * w_im + x_im * w_re
--!               All arithmetic is performed in fixed-point Q(0,-31) format
--!               (i.e., 1 integer bit and 31 fractional bits). The result is
--!               resized to DATA_WIDTH bits with saturation and rounding.
--! @param[in]    DATA_WIDTH     Width of input/output data (default 32).
--! @param[in]    WEIGHT_WIDTH   Unused but kept for compatibility (default 32).
--! @param[in]    clk            Clock signal. Operations on rising edge.
--! @param[in]    reset          Synchronous reset (active high). Clears outputs
--!                              and data_out_ready.
--! @param[in]    data_in_ready  Input valid flag. When '1', the multiplication
--!                              is performed on the current inputs.
--! @param[in]    x_re           Real part of x (signed vector).
--! @param[in]    x_im           Imaginary part of x (signed vector).
--! @param[in]    w_re           Real part of w (twiddle factor).
--! @param[in]    w_im           Imaginary part of w.
--! @param[out]   data_out_ready Output valid flag. Asserted for one clock cycle
--!                              when y_re and y_im are valid.
--! @param[out]   y_re           Real part of product (signed vector).
--! @param[out]   y_im           Imaginary part of product.
-- ============================================================================
entity multiplier is
    generic(
        DATA_WIDTH   : integer := 32;
        WEIGHT_WIDTH : integer := 32
    );
    port(
        clk            : in  std_logic;
        reset          : in  std_logic;
        data_in_ready  : in  std_logic;
        x_re           : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        x_im           : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        w_re           : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        w_im           : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_out_ready : out std_logic;
        y_re           : out std_logic_vector(DATA_WIDTH-1 downto 0);
        y_im           : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end multiplier;

-- ============================================================================
--! @brief        Architecture Behavioral implements the complex multiplication.
--! @details      The process FIXED_TWO_PHASE_CFO performs all calculations
--!               in a single clock cycle. It uses variables of type sfixed
--!               for intermediate products, then resizes the results to avoid
--!               overflow. The outputs are registered to improve timing.
-- ============================================================================
architecture Behavioral of multiplier is

    --! @brief        Registered output for real part.
    --! @details      Holds the computed real product until next valid input.
    signal y_reg_re : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    
    --! @brief        Registered output for imaginary part.
    signal y_reg_im : signed(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    -- ==========================================================================
    --! @brief        Main synchronous process for complex multiplication.
    --! @details      On each rising clock edge:
    --!               - If reset = '1', clear output ready and result registers.
    --!               - Else:
    --!                 - Deassert data_out_ready by default.
    --!                 - If data_in_ready = '1':
    --!                    - Convert input vectors to sfixed Q(0,-DATA_WIDTH+1).
    --!                    - Compute the four product terms using fixed-point
    --!                      multiplication with saturation and rounding.
    --!                    - Form final result: y_re = product1 - product2,
    --!                      y_im = product3 + product4.
    --!                    - Resize to DATA_WIDTH bits and store in output
    --!                      registers.
    --!                    - Assert data_out_ready for one cycle.
    --! @note         The fixed_point arithmetic uses Q(0,-31) format, meaning
    --!               numbers range from -1.0 to +0.999999... This matches the
    --!               twiddle ROM and butterfly outputs.
    -- ==========================================================================
    FIXED_TWO_PHASE_CFO : process(clk)

        --! @brief        Intermediate product: x_re * w_re
        variable y1_reg_re : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Intermediate product: x_im * w_im
        variable y2_reg_re : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Intermediate product: x_re * w_im
        variable y1_reg_im : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Intermediate product: x_im * w_re
        variable y2_reg_im : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');

        --! @brief        Fixed-point representation of x_re
        variable x_re_fix : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Fixed-point representation of x_im
        variable x_im_fix : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Fixed-point representation of w_re
        variable w_re_fix : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
        --! @brief        Fixed-point representation of w_im
        variable w_im_fix : sfixed(0 downto -DATA_WIDTH+1) := (others => '0');
    begin

        if rising_edge(clk) then
            if reset = '1' then
                data_out_ready <= '0';
                y_reg_re <= (others => '0');
                y_reg_im <= (others => '0');
            else
                data_out_ready <= '0';

                if data_in_ready = '1' then
                    data_out_ready <= '1';

                    -- ------------------------------------------------------------
                    -- Convert input vectors to fixed-point representation
                    -- ------------------------------------------------------------
                    x_re_fix := to_sfixed(x_re, x_re_fix'high, x_re_fix'low);
                    x_im_fix := to_sfixed(x_im, x_im_fix'high, x_im_fix'low);
                    w_re_fix := to_sfixed(w_re, w_re_fix'high, w_re_fix'low);
                    w_im_fix := to_sfixed(w_im, w_im_fix'high, w_im_fix'low);

                    -- ------------------------------------------------------------
                    -- Compute the four product terms of the complex multiply
                    -- Each product is resized to maintain the fixed-point format
                    -- and prevent overflow (saturation) and rounding.
                    -- ------------------------------------------------------------
                    y1_reg_re := resize(x_re_fix * w_re_fix, y1_reg_re'high, y1_reg_re'low, fixed_saturate, fixed_round);
                    y2_reg_re := resize(x_im_fix * w_im_fix, y2_reg_re'high, y2_reg_re'low, fixed_saturate, fixed_round);
                    y1_reg_im := resize(x_re_fix * w_im_fix, y1_reg_im'high, y1_reg_im'low, fixed_saturate, fixed_round);
                    y2_reg_im := resize(x_im_fix * w_re_fix, y2_reg_im'high, y2_reg_im'low, fixed_saturate, fixed_round);

                    -- ------------------------------------------------------------
                    -- Form final complex result
                    -- y_re = x_re*w_re - x_im*w_im
                    -- y_im = x_re*w_im + x_im*w_re
                    -- ------------------------------------------------------------
                    y_reg_re <= resize(signed(to_slv(y1_reg_re)), DATA_WIDTH) -
                                resize(signed(to_slv(y2_reg_re)), DATA_WIDTH);

                    y_reg_im <= resize(signed(to_slv(y1_reg_im)), DATA_WIDTH) +
                                resize(signed(to_slv(y2_reg_im)), DATA_WIDTH);
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    --! @brief        Output assignments.
    --! @details      Convert the internal signed registers to std_logic_vector.
    -- ==========================================================================
    y_re <= std_logic_vector(y_reg_re);
    y_im <= std_logic_vector(y_reg_im);

end Behavioral;