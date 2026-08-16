library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- 按鍵去彈跳:
-- 兩級同步化 (避免 metastability) + 穩定時間計數，確認訊號穩定 DEBOUNCE_LIMIT
-- 個 clk 週期後才承認變化，並在確認的上升緣輸出一個 clk 寬度的脈波 btn_out
entity debounce is
    generic (
        DEBOUNCE_LIMIT : integer := 1_000_000   -- 100MHz 下約 10ms
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        btn_in    : in  std_logic;              -- 實體按鍵/開關原始訊號
        btn_out   : out std_logic;              -- 去彈跳後的單週期脈波 (按鍵用)
        btn_level : out std_logic               -- 去彈跳後的穩定電位 (開關用，如 SW0)
    );
end debounce;

architecture Behavioral of debounce is
    signal cnt                  : integer range 0 to DEBOUNCE_LIMIT - 1 := 0;
    signal btn_stable           : std_logic := '0';
    signal btn_sync0, btn_sync1 : std_logic := '0';
    signal btn_prev             : std_logic := '0';
begin
    -- 兩級同步化
    process(clk)
    begin
        if rising_edge(clk) then
            btn_sync0 <= btn_in;
            btn_sync1 <= btn_sync0;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            cnt        <= 0;
            btn_stable <= '0';
            btn_prev   <= '0';
            btn_out    <= '0';
        elsif rising_edge(clk) then
            btn_out  <= '0';
            btn_prev <= btn_stable;

            if btn_sync1 = btn_stable then
                cnt <= 0;
            else
                if cnt = DEBOUNCE_LIMIT - 1 then
                    btn_stable <= btn_sync1;
                    cnt        <= 0;
                else
                    cnt <= cnt + 1;
                end if;
            end if;

            if btn_stable = '1' and btn_prev = '0' then
                btn_out <= '1';        -- 偵測到確認後的上升緣
            end if;
        end if;
    end process;

    btn_level <= btn_stable;
end Behavioral;