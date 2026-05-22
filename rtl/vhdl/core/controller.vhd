-- ============================================================================
--! @file         controller.vhd
--! @brief        Control unit for a single FFT stage (radix-2 SDF).
--! @details      This controller generates the read enable signal for the
--!               input FIFO, the mode signal for the butterfly, and the
--!               address for the twiddle ROM. It implements a three-state
--!               finite state machine (IDLE, STATE0, STATE1) that sequences
--!               the FFT stage operations based on the number of points
--!               (N_STAGE) and the overall FFT size (N_FFT). It also counts
--!               groups of butterflies (N_COUNTER = 2*N_FFT/N_STAGE).
--! @author       Duval MAMBOU
--! @date         2026
--! @version      1.0
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
--! @brief        Controller entity for one FFT stage.
--! @details      The controller sequences the processing of a stage in three
--!               main phases:
--!               - IDLE   : Fills the internal FIFO (routing mode).
--!               - STATE0 : Processing with twiddle address = 0.
--!               - STATE1 : Processing with incrementing twiddle address.
--!               The two processing phases alternate for each group of
--!               butterflies. The number of groups is N_COUNTER.
--! @param[in]    N_STAGE       Number of points for this stage (must be even).
--! @param[in]    N_FFT         Total FFT size (power of two).
--! @param[in]    ADD_WIDTH     Bit width of the twiddle address output.
--! @param[in]    clk           Clock input. All operations on rising edge.
--! @param[in]    reset         Synchronous reset (active high). Resets all
--!                             internal counters and returns to IDLE state.
--! @param[in]    data_in_ready Input data valid. Used to advance the state.
--! @param[out]   en_read_fifo  Enable signal for reading the stage FIFO.
--!                             It is gated with data_in_ready during active
--!                             processing intervals.
--! @param[out]   mode          Butterfly mode: '1' = computation,
--!                             '0' = routing (used during IDLE and some
--!                             transitions).
--! @param[out]   add_w         Twiddle ROM address (width ADD_WIDTH).
-- ============================================================================
entity controller is
    generic(
        N_STAGE   : integer := 128;
        N_FFT     : integer := 128;
        ADD_WIDTH : integer := 6
    );
    port(
        clk           : in  std_logic;
        reset         : in  std_logic;
        data_in_ready : in  std_logic;
        en_read_fifo  : out std_logic;
        mode          : out std_logic;
        add_w         : out std_logic_vector(ADD_WIDTH-1 downto 0)
    );
end controller;

-- ============================================================================
--! @brief        Architecture Behavioral implements the FSM and counters.
--! @details      The controller uses the constant N_COUNTER which represents
--!               the number of butterfly groups (or periods) to process for
--!               the current stage. The state machine ensures that each group
--!               alternates between zero-twiddle and incrementing-twiddle
--!               phases. The FIFO read enable output is combinatorial and
--!               gated with data_in_ready to prevent invalid reads.
-- ============================================================================
architecture Behavioral of controller is

    --! @brief        Number of groups (processing cycles) for this stage.
    --! @details      For a radix-2 SDF, the number of groups is 2*N_FFT/N_STAGE.
    constant N_COUNTER : integer := 2 * N_FFT / N_STAGE;

    --! @brief        States of the controller FSM.
    --! @details      - IDLE   : Initial fill / idle state.
    --!               - STATE0 : Processing with twiddle address forced to 0.
    --!               - STATE1 : Processing with twiddle address incrementing.
    type state_t is (IDLE, STATE0, STATE1);

    --! @brief        Counter for the number of processed samples within a half-stage.
    signal counter          : integer range 0 to 128 := 0;
    --! @brief        Counter for the number of processed groups.
    signal counter0         : integer                := 0;
    --! @brief        Registered version of en_read_fifo (internal to the FSM).
    signal en_read_fifo_reg : std_logic := '0';
    --! @brief        Current state of the FSM.
    signal state            : state_t := IDLE;

begin

    -- ==========================================================================
    --! @brief        Main synchronous FSM process.
    --! @details      The FSM updates on each rising clock edge.
    --!               - Reset clears all counters, sets mode = '0', add_w = 0,
    --!                 en_read_fifo_reg = '0', and goes to IDLE.
    --!               - IDLE state: waits for data_in_ready. On each valid input,
    --!                 increments counter. When counter reaches N_STAGE/2-1,
    --!                 it moves to STATE0, enables read FIFO, sets mode = '1',
    --!                 and increments counter0.
    --!               - STATE0 state: uses add_w = 0 for the whole group.
    --!                 Counts inputs until counter = N_STAGE/2-1, then moves
    --!                 to STATE1, sets mode = '0', increments counter0.
    --!               - STATE1 state: while counter0 < N_COUNTER, uses add_w = counter
    --!                 (which increments each cycle). When counter reaches
    --!                 N_STAGE/2-1, returns to STATE0, sets mode = '1',
    --!                 increments counter0. When all groups are done (counter0
    --!                 equals N_COUNTER), it outputs the remaining twiddle
    --!                 addresses (one per cycle) until counter reaches
    --!                 N_STAGE/2-1, then returns to IDLE and clears en_read_fifo_reg.
    --! @note         The twiddle address space is N_STAGE/2 (only half the
    --!               circle because the ROM stores only half of the coefficients).
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter          <= 0;
                counter0         <= 0;
                mode             <= '0';
                add_w            <= std_logic_vector(to_unsigned(0, ADD_WIDTH));
                en_read_fifo_reg <= '0';
                state            <= IDLE;

            else
                case state is

                    ----------------------------------------------------------------
                    -- Initial filling phase (routing mode)
                    ----------------------------------------------------------------
                    when IDLE =>
                        mode             <= '0';
                        en_read_fifo_reg <= '0';

                        if data_in_ready = '1' then
                            add_w   <= std_logic_vector(to_unsigned(0, ADD_WIDTH));
                            counter <= counter + 1;

                            if counter = N_STAGE/2 - 1 then
                                counter          <= 0;
                                en_read_fifo_reg <= '1';
                                mode             <= '1';
                                counter0         <= counter0 + 1;
                                state            <= STATE0;
                            end if;
                        end if;

                    ----------------------------------------------------------------
                    -- Processing phase with zero twiddle address
                    ----------------------------------------------------------------
                    when STATE0 =>
                        if data_in_ready = '1' then
                            add_w   <= std_logic_vector(to_unsigned(0, ADD_WIDTH));
                            counter <= counter + 1;

                            if counter = N_STAGE/2 - 1 then
                                counter  <= 0;
                                mode     <= '0';
                                counter0 <= counter0 + 1;
                                state    <= STATE1;
                            end if;
                        end if;

                    ----------------------------------------------------------------
                    -- Processing phase with incrementing twiddle address
                    ----------------------------------------------------------------
                    when STATE1 =>
                        if counter0 < N_COUNTER then
                            if data_in_ready = '1' then
                                add_w   <= std_logic_vector(to_unsigned(counter, ADD_WIDTH));
                                counter <= counter + 1;

                                if counter = N_STAGE/2 - 1 then
                                    counter  <= 0;
                                    mode     <= '1';
                                    counter0 <= counter0 + 1;
                                    state    <= STATE0;
                                end if;
                            end if;

                        else
                            -- All groups completed: output remaining addresses if any
                            add_w <= std_logic_vector(to_unsigned(counter, ADD_WIDTH));

                            if counter < (N_STAGE/2 - 1) then
                                counter <= counter + 1;
                            else
                                counter0         <= 0;
                                counter          <= 0;
                                en_read_fifo_reg <= '0';
                                state            <= IDLE;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- ==========================================================================
    --! @brief        Combinatorial generation of en_read_fifo.
    --! @details      During active group processing (counter0 < N_COUNTER),
    --!               en_read_fifo is the AND of the registered enable and
    --!               data_in_ready. Otherwise, it equals the registered enable
    --!               (which is typically '0' except during the final address
    --!               dump phase). This gating prevents reading from the FIFO
    --!               when input data is not valid.
    -- ==========================================================================
    en_read_fifo <= (en_read_fifo_reg and data_in_ready)
                    when (counter0 < N_COUNTER)
                    else en_read_fifo_reg;

end Behavioral;