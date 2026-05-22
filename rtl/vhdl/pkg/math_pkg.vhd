

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package math_pkg is

    --------------------------------------------------------------------------
    -- Return the ceiling of log2(n)
    --------------------------------------------------------------------------
    function clog2(n : integer) return integer;

end package math_pkg;


package body math_pkg is

    function clog2(n : integer) return integer is
        variable v   : integer := 0;
        variable val : integer := n - 1;
    begin
        ----------------------------------------------------------------------
        -- Handle small values to avoid zero-width results
        ----------------------------------------------------------------------
        if n <= 1 then
            return 1;
        end if;

        ----------------------------------------------------------------------
        -- Compute ceil(log2(n)) using iterative division
        ----------------------------------------------------------------------
        while val > 0 loop
            val := val / 2;
            v   := v + 1;
        end loop;

        return v;
    end function;

end package body math_pkg;