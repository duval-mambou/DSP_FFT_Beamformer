-- ============================================================================
--! @file         twiddle_rom.vhd
--! @brief        ROM storing twiddle factors for FFT butterflies.
--! @details      This module generates a ROM containing complex twiddle factors
--!               of the form W_N^k = exp(-j*2*pi*k/N_STAGE). The values are
--!               precomputed at elaboration time using the math_real library
--!               and stored in fixed-point Q(0,-DATA_W+1) format.
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use ieee.fixed_pkg.all;

-- ============================================================================
--! @brief        Twiddle factor ROM entity.
--! @details      The ROM contains N_STAGE/2 complex twiddle factors, i.e.,
--!               the non-redundant half of the unit circle. Addresses beyond
--!               this range output zero. The twiddle values are precomputed
--!               using the formula: W_N^k = cos(-2?k/N) + j*sin(-2?k/N).
--! @param[in]    ADDR_W      Address width in bits (default 6).
--! @param[in]    DATA_W      Data width of each fixed-point value (default 32).
--! @param[in]    N_STAGE     Number of points for this stage (default 128).
--!                           Must be a power of two. The ROM size is N_STAGE/2.
--! @param[in]    addr_i      Read address (vector, ADDR_W bits).
--! @param[out]   twiddle_re_o Real part (cosine) of the twiddle factor.
--! @param[out]   twiddle_im_o Imaginary part (negative sine) of the twiddle factor.
-- ============================================================================
entity twidle_rom is
    generic(
        ADDR_W  : natural := 6;
        DATA_W  : natural := 32;
        N_STAGE : natural := 128
    );
    port(
        addr_i        : in  std_logic_vector(ADDR_W-1 downto 0);
        twiddle_re_o  : out std_logic_vector(DATA_W-1 downto 0);
        twiddle_im_o  : out std_logic_vector(DATA_W-1 downto 0)
    );
end entity;

-- ============================================================================
--! @brief        Architecture twiddle_rom_arch implements ROM with functions.
--! @details      Two ROM arrays (real and imaginary) are initialized using
--!               generate statements. Each coefficient is computed by a
--!               function that returns a std_logic_vector in fixed-point
--!               format. The read is combinatorial (asynchronous).
-- ============================================================================
architecture twiddle_rom_arch of twidle_rom is

    --! @brief        ROM type definition: array of std_logic_vector.
    type rom_type is array (natural range <>) of std_logic_vector(DATA_W-1 downto 0);

    --! @brief        Function that returns the real part (cosine) for index k.
    --! @param[in]    k       Index in range 0 to N_STAGE/2 - 1.
    --! @return       std_logic_vector containing cos(-2?k/N) in Q(0,-DATA_W+1).
    function tw_re(k : natural) return std_logic_vector is
        variable angle : real;
        variable val   : real;
    begin
        angle := -2.0 * math_pi * real(k) / real(N_STAGE);
        val   := cos(angle);
        return to_slv(to_sfixed(val, 0, -DATA_W+1));
    end function;

    --! @brief        Function that returns the imaginary part (sine) for index k.
    --! @param[in]    k       Index in range 0 to N_STAGE/2 - 1.
    --! @return       std_logic_vector containing sin(-2?k/N) in Q(0,-DATA_W+1).
    function tw_im(k : natural) return std_logic_vector is
        variable angle : real;
        variable val   : real;
    begin
        angle := -2.0 * math_pi * real(k) / real(N_STAGE);
        val   := sin(angle);
        return to_slv(to_sfixed(val, 0, -DATA_W+1));
    end function;

    --! @brief        ROM storage for real parts (cosine).
    signal ROM_RE : rom_type(0 to N_STAGE/2 - 1);
    --! @brief        ROM storage for imaginary parts (sine).
    signal ROM_IM : rom_type(0 to N_STAGE/2 - 1);

begin

    -- ==========================================================================
    --! @brief        Generate ROM contents at elaboration time.
    --! @details      For each index i from 0 to N_STAGE/2-1, compute and store
    --!               the corresponding real and imaginary twiddle coefficients.
    -- ==========================================================================
    GEN_ROM : for i in 0 to N_STAGE/2 - 1 generate
    begin
        ROM_RE(i) <= tw_re(i);
        ROM_IM(i) <= tw_im(i);
    end generate;

    -- ==========================================================================
    --! @brief        Asynchronous ROM read process.
    --! @details      The address is converted to an integer. If the address is
    --!               within the valid range (0 to N_STAGE/2-1), the corresponding
    --!               ROM entry is output; otherwise, both outputs are set to zero.
    --! @note         This is a combinatorial read (no clock), suitable for
    --!               small ROMs. For larger ROMs, a registered output may be
    --!               required to meet timing.
    -- ==========================================================================
    process(addr_i)
        variable idx : natural;
    begin
        idx := to_integer(unsigned(addr_i));

        if idx > (N_STAGE/2 - 1) then
            twiddle_re_o <= (others => '0');
            twiddle_im_o <= (others => '0');
        else
            twiddle_re_o <= ROM_RE(idx);
            twiddle_im_o <= ROM_IM(idx);
        end if;
    end process;

end architecture;