library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- 獨立、可重用的單一數字繪製模組。仿照7段顯示器的邏輯，把 0~9 拆成 7 畫
-- (a~g)，每一畫對應數字方框裡的一個矩形區域，用矩形色塊拼出來--不用額外
-- 的 font ROM/.coe 檔，純組合邏輯，跟 Project7 那種 BRAM 讀取延遲完全無關。
--
--      _a_
--    f|   |b
--      _g_
--    e|   |c
--      _d_
--
-- 座標系統是「相對座標」，不是螢幕絕對座標：呼叫端(渲染模組/頂層)自己決定
-- 這個數字要畫在螢幕的哪個絕對位置，把 pixel_x/pixel_y 減去數字左上角座標
-- 之後才送進來這裡的 rel_x/rel_y。這樣這個模組完全不知道自己被畫在螢幕
-- 哪裡，之後任何專案只要想在畫面上顯示數字，都能直接搬過去用，不用改。
--
-- 只顯示單一個 0~9 的數字；多位數(例如兩位數比分)由呼叫端自己算出十位、
-- 個位各是多少，分別各接一顆這個模組的 instance，這裡不處理除法/多位數。
entity digit_font is
    generic (
        DIGIT_W : integer := 30;  -- 數字方框寬度(pixel)
        DIGIT_H : integer := 50;  -- 數字方框高度(pixel)
        SEG_T   : integer := 6    -- 每一畫的粗細(pixel)
    );
    port (
        digit_value : in  unsigned(3 downto 0);   -- 0~9；10~15 視為不顯示(全暗)
        rel_x       : in  unsigned(15 downto 0);  -- 相對這個數字左上角的座標，範圍 0~DIGIT_W-1
        rel_y       : in  unsigned(15 downto 0);  -- 範圍 0~DIGIT_H-1
        pixel_on    : out std_logic               -- 這個相對座標該不該點亮
    );
end digit_font;

architecture Behavioral of digit_font is

    -- ===== 幾何判斷：這個相對座標落在哪一畫的矩形範圍內 =====
    -- 純粹跟座標有關，跟 digit_value(要顯示哪個數字)完全無關。允許畫跟畫
    -- 之間在角落有一點重疊(例如 a 跟 f 都覆蓋到左上角那幾個pixel)，重疊處
    -- 顯示的顏色是一樣的，不會有視覺衝突，故意不刻意切齊避免留白縫隙。
    signal in_a, in_b, in_c, in_d, in_e, in_f, in_g : std_logic;

    -- ===== 查表：這個數字要點亮哪幾畫 =====
    signal on_a, on_b, on_c, on_d, on_e, on_f, on_g : std_logic;

begin

    in_a <= '1' when (rel_y < SEG_T) else '0';
    in_d <= '1' when (rel_y >= DIGIT_H - SEG_T) else '0';
    in_g <= '1' when (rel_y >= (DIGIT_H - SEG_T) / 2 and rel_y < (DIGIT_H - SEG_T) / 2 + SEG_T) else '0';

    in_f <= '1' when (rel_x < SEG_T and rel_y < DIGIT_H / 2) else '0';
    in_b <= '1' when (rel_x >= DIGIT_W - SEG_T and rel_y < DIGIT_H / 2) else '0';
    in_e <= '1' when (rel_x < SEG_T and rel_y >= DIGIT_H / 2) else '0';
    in_c <= '1' when (rel_x >= DIGIT_W - SEG_T and rel_y >= DIGIT_H / 2) else '0';

    process(digit_value)
    begin
        -- 預設全暗，0~9 才會被下面覆蓋成正確組合；10~15 保持全暗
        on_a <= '0'; on_b <= '0'; on_c <= '0'; on_d <= '0';
        on_e <= '0'; on_f <= '0'; on_g <= '0';
        case to_integer(digit_value) is
            when 0 => on_a<='1'; on_b<='1'; on_c<='1'; on_d<='1'; on_e<='1'; on_f<='1'; on_g<='0';
            when 1 => on_a<='0'; on_b<='1'; on_c<='1'; on_d<='0'; on_e<='0'; on_f<='0'; on_g<='0';
            when 2 => on_a<='1'; on_b<='1'; on_c<='0'; on_d<='1'; on_e<='1'; on_f<='0'; on_g<='1';
            when 3 => on_a<='1'; on_b<='1'; on_c<='1'; on_d<='1'; on_e<='0'; on_f<='0'; on_g<='1';
            when 4 => on_a<='0'; on_b<='1'; on_c<='1'; on_d<='0'; on_e<='0'; on_f<='1'; on_g<='1';
            when 5 => on_a<='1'; on_b<='0'; on_c<='1'; on_d<='1'; on_e<='0'; on_f<='1'; on_g<='1';
            when 6 => on_a<='1'; on_b<='0'; on_c<='1'; on_d<='1'; on_e<='1'; on_f<='1'; on_g<='1';
            when 7 => on_a<='1'; on_b<='1'; on_c<='1'; on_d<='0'; on_e<='0'; on_f<='0'; on_g<='0';
            when 8 => on_a<='1'; on_b<='1'; on_c<='1'; on_d<='1'; on_e<='1'; on_f<='1'; on_g<='1';
            when 9 => on_a<='1'; on_b<='1'; on_c<='1'; on_d<='1'; on_e<='0'; on_f<='1'; on_g<='1';
            when others => null;  -- 保持全暗
        end case;
    end process;

    pixel_on <= (in_a and on_a) or (in_b and on_b) or (in_c and on_c) or
                (in_d and on_d) or (in_e and on_e) or (in_f and on_f) or (in_g and on_g);

end Behavioral;