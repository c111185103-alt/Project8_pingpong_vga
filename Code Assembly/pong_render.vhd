library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Project8 畫面渲染模組。拿 vga_timing 送出的 pixel_x/pixel_y（目前正在
-- 掃描哪個座標）跟 pong_game 送出的球/兩支球拍座標比對，決定當下這個 pixel 該
-- 輸出什麼顏色。
--
-- 純組合邏輯，完全沒有 clk/rst--這點跟 vga_photo_top(Project7) 不一樣：那邊因為
-- BRAM 讀取有 1 拍延遲，一定要額外做延遲register對齊；這裡 ball_x/ball_y/
-- paddle_a_y/paddle_b_y 全部都是 pong_game 已經算好的純暫存器輸出，跟 pixel_x/
-- pixel_y 是同一拍就緒的組合邏輯，直接比較，不需要任何延遲對齊。
--
-- 配色比照經典 Atari Pong：黑底白圖，球拍跟球都是白色，不特別分色。
--
-- 分數的數字畫法不在這裡處理，留給另一個獨立模組(digit_font)，這裡只負責
-- 球/球拍/背景。
entity pong_render is
    generic (
        SCREEN_W   : integer := 640;
        SCREEN_H   : integer := 480;
        PADDLE_W   : integer := 10;
        PADDLE_H   : integer := 60;
        PADDLE_A_X : integer := 20;   -- 跟 pong_game 同一組數字，兩邊一定要一致
        PADDLE_B_X : integer := 610;  -- 座標系統才對得起來
        BALL_SIZE  : integer := 10
    );
    port (
        pixel_x    : in  unsigned(15 downto 0);  -- 來自 vga_timing，目前掃描到的座標
        pixel_y    : in  unsigned(15 downto 0);
        video_on   : in  std_logic;              -- 來自 vga_timing，'0'代表在消隱區間，一定要輸出全黑

        ball_x     : in  unsigned(15 downto 0);  -- 以下四個都來自 pong_game
        ball_y     : in  unsigned(15 downto 0);
        paddle_a_y : in  unsigned(15 downto 0);
        paddle_b_y : in  unsigned(15 downto 0);

        vga_r      : out std_logic_vector(3 downto 0);
        vga_g      : out std_logic_vector(3 downto 0);
        vga_b      : out std_logic_vector(3 downto 0)
    );
end pong_render;

architecture Behavioral of pong_render is

    -- 三個形狀各自獨立判斷「目前這個pixel在不在我範圍內」，用半開區間
    -- [起點, 起點+寬度) 這個慣例：起點那一列/欄算在裡面，起點+寬度那一列/欄不算，
    -- 這樣三個形狀的寬度定義才會剛好等於 PADDLE_W/PADDLE_H/BALL_SIZE，不會多1或少1。
    signal in_paddle_a : std_logic;
    signal in_paddle_b : std_logic;
    signal in_ball      : std_logic;
    signal in_shape      : std_logic;  -- 三個形狀只要有任何一個命中就算

begin

    in_paddle_a <= '1' when (pixel_x >= PADDLE_A_X and pixel_x < PADDLE_A_X + PADDLE_W and
                              pixel_y >= paddle_a_y and pixel_y < paddle_a_y + PADDLE_H)
                   else '0';

    in_paddle_b <= '1' when (pixel_x >= PADDLE_B_X and pixel_x < PADDLE_B_X + PADDLE_W and
                              pixel_y >= paddle_b_y and pixel_y < paddle_b_y + PADDLE_H)
                   else '0';

    in_ball <= '1' when (pixel_x >= ball_x and pixel_x < ball_x + BALL_SIZE and
                          pixel_y >= ball_y and pixel_y < ball_y + BALL_SIZE)
               else '0';

    -- 三個形狀配色一樣(全白)，命中誰都無所謂，直接OR起來即可，不用排優先權。
    in_shape <= in_paddle_a or in_paddle_b or in_ball;

    vga_r <= "1111" when (video_on = '1' and in_shape = '1') else "0000";
    vga_g <= "1111" when (video_on = '1' and in_shape = '1') else "0000";
    vga_b <= "1111" when (video_on = '1' and in_shape = '1') else "0000";

end Behavioral;