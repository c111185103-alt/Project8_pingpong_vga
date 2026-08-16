library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- 專門給 pong_top.vhd 贏球畫面用的字母繪製模組，畫 W / I / N 三個字母。
-- 跟 digit_font.vhd 不同：digit_font 是仿7段顯示器、用矩形拼筆畫；這裡
-- W 沒辦法用7段邏輯拼得像樣(對角線這種形狀矩形筆畫做不出來)，改用
-- 5行x7列的小點陣網格去畫每個字母--同樣不用額外的font ROM/.coe檔，
-- 網格圖案直接寫死成常數陣列，純組合邏輯查表決定每個相對座標該不該點亮。
--
-- 座標系統一樣是「相對座標」，不是螢幕絕對座標，跟 digit_font.vhd 同一個
-- 設計哲學：這個模組不知道自己被畫在螢幕哪裡，呼叫端(pong_top.vhd)自己決定
-- 絕對位置、算出相對座標再送進來。
entity letter_font is
    generic (
        LETTER_W : integer := 60;  -- 字母方框寬度(pixel)，5欄，建議可被5整除
        LETTER_H : integer := 84   -- 字母方框高度(pixel)，7列，建議可被7整除
    );
    port (
        letter_sel : in  unsigned(1 downto 0);   -- 0=W, 1=I, 2=N，其餘視為不顯示(全暗)
        rel_x      : in  unsigned(15 downto 0);  -- 相對這個字母左上角的座標，範圍 0~LETTER_W-1
        rel_y      : in  unsigned(15 downto 0);  -- 範圍 0~LETTER_H-1
        pixel_on   : out std_logic
    );
end letter_font;

architecture Behavioral of letter_font is

    type row_pattern_t is array (0 to 6) of std_logic_vector(4 downto 0);

    -- 每個字母 7 列 x 5 欄，'1'=這一格要點亮。由左到右、由上到下。
    constant PATTERN_W : row_pattern_t := (
        "10001",
        "10001",
        "10001",
        "10101",
        "10101",
        "11011",
        "10001"
    );

    constant PATTERN_I : row_pattern_t := (
        "01110",
        "00100",
        "00100",
        "00100",
        "00100",
        "00100",
        "01110"
    );

    constant PATTERN_N : row_pattern_t := (
        "10001",
        "11001",
        "10101",
        "10101",
        "10011",
        "10001",
        "10001"
    );

begin

    process(letter_sel, rel_x, rel_y)
        variable row, col     : integer;
        variable selected_row : std_logic_vector(4 downto 0);
    begin
        row := to_integer(rel_y) / (LETTER_H / 7);
        col := to_integer(rel_x) / (LETTER_W / 5);

        if row < 0 or row > 6 or col < 0 or col > 4 then
            -- 呼叫端如果不小心餵進超出範圍的相對座標(例如減法underflow繞成
            -- 很大的數)，這裡直接視為不點亮，不去索引陣列，避免異常
            pixel_on <= '0';
        else
            case letter_sel is
                when "00"   => selected_row := PATTERN_W(row);
                when "01"   => selected_row := PATTERN_I(row);
                when "10"   => selected_row := PATTERN_N(row);
                when others => selected_row := "00000";
            end case;
            pixel_on <= selected_row(4 - col);
        end if;
    end process;

end Behavioral;