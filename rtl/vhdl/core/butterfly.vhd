-- ============================================================================
--! @file         butterfly.vhd
--! @brief        Radix-2 butterfly unit for FFT datapath.
--! @details      This module implements a butterfly operation used in radix-2
--!               FFT. It supports two modes:
--!               - mode = '1' : computation (add/sub with division by 2)
--!               - mode = '0' : routing (cross-connect for initial fill)
--!               All operands are signed fixed-point numbers in Q(1,31) format
--!               represented as std_logic_vector(DATA_WIDTH-1 downto 0).
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
--! @brief        Butterfly entity.
--! @details      In computation mode (mode = '1'), when both x1_ready and
--!               x2_ready are asserted, the butterfly computes:
--!               y1 = (x1 - x2) / 2   and   y2 = (x1 + x2) / 2.
--!               The division by 2 avoids overflow and is implemented as
--!               a right shift after performing the addition/subtraction on
--!               extended (DATA_WIDTH+1)-bit vectors.
--!               In routing mode (mode = '0'), the unit simply forwards:
--!               x1 -> y2   and   x2 -> y1.
--! @param[in]    DATA_WIDTH   Data width in bits (default 32).
--! @param[in]    clk          Clock input. All operations on rising edge.
--! @param[in]    reset        Synchronous reset (active high). Clears all
--!                            internal registers and output handshake flags.
--! @param[in]    mode         Control signal: '1' = computation, '0' = routing.
--! @param[in]    x1_ready     Indicates that x1_re and x1_im are valid.
--! @param[in]    x2_ready     Indicates that x2_re and x2_im are valid.
--! @param[in]    x1_re        Real part of first operand.
--! @param[in]    x1_im        Imaginary part of first operand.
--! @param[in]    x2_re        Real part of second operand.
--! @param[in]    x2_im        Imaginary part of second operand.
--! @param[out]   y1_ready     Valid flag for y1 outputs.
--! @param[out]   y2_ready     Valid flag for y2 outputs.
--! @param[out]   y1_re        Real part of first result.
--! @param[out]   y1_im        Imaginary part of first result.
--! @param[out]   y2_re        Real part of second result.
--! @param[out]   y2_im        Imaginary part of second result.
-- ============================================================================
entity butterfly is
    generic(
        DATA_WIDTH : integer := 32
    );
    port(
        clk      : in  std_logic;
        reset    : in  std_logic;
        mode     : in  std_logic;
        x1_ready : in  std_logic;
        x2_ready : in  std_logic;
        x1_re    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        x1_im    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        x2_re    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        x2_im    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        y1_ready : out std_logic;
        y2_ready : out std_logic;
        y1_re    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        y1_im    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        y2_re    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        y2_im    : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end butterfly;

-- ============================================================================
--! @brief        Architecture Behavioral implements the butterfly datapath.
--! @details      The results are computed using signed arithmetic with an
--!               extra guard bit to protect against overflow. The division
--!               by 2 is done by a right shift. In routing mode, the unit
--!               simply copies input values to the opposite output ports
--!               after sign-extending them to (DATA_WIDTH+1) bits to keep
--!               the internal format consistent.
-- ============================================================================
architecture Behavioral of butterfly is

    --! @brief        Internal registered result for y1 real part.
    --! @details      Uses one extra bit (DATA_WIDTH downto 0) for safe arithmetic.
    signal y1_reg_re : signed(DATA_WIDTH downto 0) := (others => '0');
    --! @brief        Internal registered result for y2 real part.
    signal y2_reg_re : signed(DATA_WIDTH downto 0) := (others => '0');
    --! @brief        Internal registered result for y1 imaginary part.
    signal y1_reg_im : signed(DATA_WIDTH downto 0) := (others => '0');
    --! @brief        Internal registered result for y2 imaginary part.
    signal y2_reg_im : signed(DATA_WIDTH downto 0) := (others => '0');

begin

    -- ==========================================================================
    --! @brief        Main synchronous process for butterfly/logic.
    --! @details      On each clock edge:
    --!               - Reset clears all registers and ready flags.
    --!               - Default: deassert y1_ready and y2_ready.
    --!               - If mode = '1' (computation):
    --!                    When both x1_ready and x2_ready are '1', compute
    --!                    sum/difference, divide by 2 (shift right), store in
    --!                    internal registers, and assert both ready outputs.
    --!               - If mode = '0' (routing):
    --!                    When x1_ready = '1', forward x1 to y2 (with sign extend).
    --!                    When x2_ready = '1', forward x2 to y1.
    --! @note         The division by 2 prevents overflow when the two inputs
    --!               have the same sign and magnitude close to full scale.
    -- ==========================================================================
    FIXED_TWO_PHASE_CFO : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                y1_ready <= '0';
                y2_ready <= '0';
                y1_reg_re <= (others => '0');
                y2_reg_re <= (others => '0');
                y1_reg_im <= (others => '0');
                y2_reg_im <= (others => '0');

            else
                -- Default: no outputs valid
                y1_ready <= '0';
                y2_ready <= '0';

                if mode = '1' then
                    -- ------------------------------------------------------------
                    -- Computation mode: perform radix-2 butterfly
                    -- y1 = (x1 - x2) / 2
                    -- y2 = (x1 + x2) / 2
                    -- ------------------------------------------------------------
                    if (x1_ready = '1' and x2_ready = '1') then
                        -- Real part
                        y1_reg_re <= shift_right(resize(signed(x1_re), DATA_WIDTH+1) - resize(signed(x2_re), DATA_WIDTH+1), 1);
                        y2_reg_re <= shift_right(resize(signed(x1_re), DATA_WIDTH+1) + resize(signed(x2_re), DATA_WIDTH+1), 1);
                        -- Imaginary part
                        y1_reg_im <= shift_right(resize(signed(x1_im), DATA_WIDTH+1) - resize(signed(x2_im), DATA_WIDTH+1), 1);
                        y2_reg_im <= shift_right(resize(signed(x1_im), DATA_WIDTH+1) + resize(signed(x2_im), DATA_WIDTH+1), 1);

                        y1_ready <= '1';
                        y2_ready <= '1';
                    end if;

                else
                    -- ------------------------------------------------------------
                    -- Routing mode: cross connection (used during initial fill)
                    -- x1 -> y2 ,  x2 -> y1
                    -- ------------------------------------------------------------
                    if x1_ready = '1' then
                        -- Sign extend x1 to (DATA_WIDTH+1) bits and route to y2
                        y2_reg_re <= signed(x1_re(DATA_WIDTH-1) & x1_re);
                        y2_reg_im <= signed(x1_im(DATA_WIDTH-1) & x1_im);
                        y2_ready  <= '1';
                    end if;

                    if x2_ready = '1' then
                        -- Sign extend x2 to (DATA_WIDTH+1) bits and route to y1
                        y1_reg_re <= signed(x2_re(DATA_WIDTH-1) & x2_re);
                        y1_reg_im <= signed(x2_im(DATA_WIDTH-1) & x2_im);
                        y1_ready  <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    --! @brief        Output truncation.
    --! @details      The internal registers have one extra guard bit. This
    --!               bit is dropped (truncation) when assigning to the
    --!               outputs, as the division by 2 already prevents overflow.
    -- ==========================================================================
    y1_re <= std_logic_vector(y1_reg_re(DATA_WIDTH-1 downto 0));
    y1_im <= std_logic_vector(y1_reg_im(DATA_WIDTH-1 downto 0));
    y2_re <= std_logic_vector(y2_reg_re(DATA_WIDTH-1 downto 0));
    y2_im <= std_logic_vector(y2_reg_im(DATA_WIDTH-1 downto 0));

end Behavioral;