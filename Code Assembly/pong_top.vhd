library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Project8 頂層：把 vga_timing(Project7沿用) + pong_game + pong_render +
-- 4 顆 digit_font(A/B 各兩位數) 接起來，輸出完整的 VGA 訊號。
--
-- rst 比照 Project7 的做法直接穿過去，不像 Project5/6 那樣另外包一層 hw_top 做
-- GRST 去彈跳--rst 直接穿透頂層，沒有額外包一層同步化。
--
-- SCREEN_W/SCREEN_H 是這個頂層唯一「三個子模組共用」的關鍵 generic：
-- 同時決定 vga_timing 的可視範圍(H_VISIBLE/V_VISIBLE)跟 pong_game/pong_render
-- 的座標系統，三邊從這裡的同一份數字往下傳，不會各自兜出不一致的畫面尺寸。
--
-- 分數數字位置採「畫面上方置中，A在左、B在右」：DIGIT_W=30，同一方的十位/
-- 個位中間留5px，A、B兩個分數區塊中間留50px，整組橫向置中對齊 SCREEN_W。
entity pong_top is
    generic (
        -- ===== 三個子模組共用的畫面幾何 =====
        SCREEN_W     : integer := 640;
        SCREEN_H     : integer := 480;
        PADDLE_W     : integer := 10;
        PADDLE_H     : integer := 60;
        PADDLE_A_X   : integer := 20;
        PADDLE_B_X   : integer := 610;
        BALL_SIZE    : integer := 10;

        -- ===== 只有 pong_game 需要 =====
        PADDLE_SPEED : integer := 4;
        BALL_SPEED   : integer := 2;
        TICK_DIVISOR : integer := 1000000;
        DEBOUNCE_LIM : integer := 1_000_000;
        WIN_SCORE    : integer := 11;
        WIN_MARGIN   : integer := 2;

        -- ===== 只有 digit_font 需要（外觀） =====
        DIGIT_W : integer := 30;
        DIGIT_H : integer := 50;
        SEG_T   : integer := 6;

        -- ===== 分數位置：畫面上方置中，A左B右 =====
        SCORE_Y  : integer := 20;
        A_TENS_X : integer := 230;
        A_ONES_X : integer := 265;
        B_TENS_X : integer := 345;
        B_ONES_X : integer := 380;

        -- ===== WIN 字樣外觀：贏家分數格直接換成WIN字樣(輸家維持顯示原本的
        --       數字)，不是畫面正中央--所以尺寸縮小配合分數格寬度(原本
        --       2個數字+5px間距?65px)，LETTER_H對齊DIGIT_H讓垂直位置一致，
        --       實際X座標(哪一側)由 winner_is_a 決定，寫在架構內部算，不是
        --       固定generic =====
        LETTER_W    : integer := 20;
        LETTER_H    : integer := 50;
        LETTER_GAP  : integer := 3
    );
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        btn_a_up_raw   : in  std_logic;
        btn_a_down_raw : in  std_logic;
        btn_b_up_raw   : in  std_logic;
        btn_b_down_raw : in  std_logic;

        hsync : out std_logic;
        vsync : out std_logic;
        vga_r : out std_logic_vector(3 downto 0);
        vga_g : out std_logic_vector(3 downto 0);
        vga_b : out std_logic_vector(3 downto 0)
    );
end pong_top;

architecture Behavioral of pong_top is

    component vga_timing is
        generic (
            H_VISIBLE     : integer := 640;
            H_FRONT_PORCH : integer := 16;
            H_SYNC_PULSE  : integer := 96;
            H_BACK_PORCH  : integer := 48;
            V_VISIBLE     : integer := 480;
            V_FRONT_PORCH : integer := 10;
            V_SYNC_PULSE  : integer := 2;
            V_BACK_PORCH  : integer := 33;
            PIXEL_DIVISOR : integer := 4
        );
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            hsync      : out std_logic;
            vsync      : out std_logic;
            video_on   : out std_logic;
            pixel_x    : out unsigned(15 downto 0);
            pixel_y    : out unsigned(15 downto 0);
            pixel_tick : out std_logic
        );
    end component;

    component pong_game is
        generic (
            SCREEN_W     : integer := 640;
            SCREEN_H     : integer := 480;
            PADDLE_W     : integer := 10;
            PADDLE_H     : integer := 60;
            PADDLE_A_X   : integer := 20;
            PADDLE_B_X   : integer := 610;
            PADDLE_SPEED : integer := 4;
            BALL_SIZE    : integer := 10;
            BALL_SPEED   : integer := 2;
            TICK_DIVISOR : integer := 1000000;
            DEBOUNCE_LIM : integer := 1_000_000;
            WIN_SCORE    : integer := 11;
            WIN_MARGIN   : integer := 2
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            btn_a_up_raw   : in  std_logic;
            btn_a_down_raw : in  std_logic;
            btn_b_up_raw   : in  std_logic;
            btn_b_down_raw : in  std_logic;
            ball_x        : out unsigned(15 downto 0);
            ball_y        : out unsigned(15 downto 0);
            paddle_a_y    : out unsigned(15 downto 0);
            paddle_b_y    : out unsigned(15 downto 0);
            score_a       : out unsigned(7 downto 0);
            score_b       : out unsigned(7 downto 0);
            game_over     : out std_logic;
            winner_is_a   : out std_logic;
            game_tick_dbg : out std_logic
        );
    end component;

    component pong_render is
        generic (
            SCREEN_W   : integer := 640;
            SCREEN_H   : integer := 480;
            PADDLE_W   : integer := 10;
            PADDLE_H   : integer := 60;
            PADDLE_A_X : integer := 20;
            PADDLE_B_X : integer := 610;
            BALL_SIZE  : integer := 10
        );
        port (
            pixel_x    : in  unsigned(15 downto 0);
            pixel_y    : in  unsigned(15 downto 0);
            video_on   : in  std_logic;
            ball_x     : in  unsigned(15 downto 0);
            ball_y     : in  unsigned(15 downto 0);
            paddle_a_y : in  unsigned(15 downto 0);
            paddle_b_y : in  unsigned(15 downto 0);
            vga_r      : out std_logic_vector(3 downto 0);
            vga_g      : out std_logic_vector(3 downto 0);
            vga_b      : out std_logic_vector(3 downto 0)
        );
    end component;

    component digit_font is
        generic (
            DIGIT_W : integer := 30;
            DIGIT_H : integer := 50;
            SEG_T   : integer := 6
        );
        port (
            digit_value : in  unsigned(3 downto 0);
            rel_x       : in  unsigned(15 downto 0);
            rel_y       : in  unsigned(15 downto 0);
            pixel_on    : out std_logic
        );
    end component;

    component letter_font is
        generic (
            LETTER_W : integer := 60;
            LETTER_H : integer := 84
        );
        port (
            letter_sel : in  unsigned(1 downto 0);
            rel_x      : in  unsigned(15 downto 0);
            rel_y      : in  unsigned(15 downto 0);
            pixel_on   : out std_logic
        );
    end component;

    signal pixel_x, pixel_y : unsigned(15 downto 0);
    signal video_on         : std_logic;

    signal ball_x, ball_y, paddle_a_y, paddle_b_y : unsigned(15 downto 0);
    signal score_a, score_b                       : unsigned(7 downto 0);
    signal game_over                              : std_logic;
    signal winner_is_a                            : std_logic;

    signal render_r, render_g, render_b : std_logic_vector(3 downto 0);

    -- 分數拆十位/個位：NUMERIC_STD 沒有定義 unsigned 的 "/" 或 "mod"，
    -- 用 to_integer 轉成整數做除法再轉回來；額外多做一次 mod 10 純粹是防呆
    -- (score_a/b 是8-bit，理論上可以到255，多一層mod 10保證十位數字絕對落在
    -- 0~9，不會超出digit_value(3 downto 0)的表示範圍造成環繞)
    signal a_tens_v, a_ones_v, b_tens_v, b_ones_v : integer range 0 to 9;
    signal digit_val_a_tens, digit_val_a_ones, digit_val_b_tens, digit_val_b_ones : unsigned(3 downto 0);

    -- 4個數字框各自的絕對座標命中判斷；rel_x/rel_y用unsigned減法算，pixel_x
    -- 小於方框起點時會underflow繞成一個很大的數，但只要用這裡的in_..._box
    -- 把關、沒命中就不採信digit_font的輸出，繞回的數字不會造成誤判
    signal in_a_tens_box, in_a_ones_box, in_b_tens_box, in_b_ones_box : std_logic;
    signal a_tens_raw, a_ones_raw, b_tens_raw, b_ones_raw             : std_logic;
    signal a_tens_on, a_ones_on, b_tens_on, b_ones_on                 : std_logic;
    signal rel_y_score                                                : unsigned(15 downto 0);
    signal rel_x_a_tens, rel_x_a_ones, rel_x_b_tens, rel_x_b_ones     : unsigned(15 downto 0);
    signal digit_hit                                                  : std_logic;

    -- WIN 三個字母：畫在贏家的分數格位置(A_TENS_X或B_TENS_X，由winner_is_a
    -- 決定)，不是固定畫面座標；跟分數數字同一套「絕對座標box-gating」邏輯，
    -- 避免rel_x/rel_y減法underflow繞成大數時被letter_font誤判成命中
    signal win_base_x                                   : natural;
    signal win_w_x, win_i_x, win_n_x                    : natural;
    signal rel_x_win_w, rel_x_win_i, rel_x_win_n        : unsigned(15 downto 0);
    signal in_win_w_box, in_win_i_box, in_win_n_box      : std_logic;
    signal win_w_raw, win_i_raw, win_n_raw               : std_logic;
    signal win_w_on, win_i_on, win_n_on                  : std_logic;
    signal win_hit                                       : std_logic;
    signal winner_slots_hit, loser_slots_hit             : std_logic;
    signal score_area_hit                                : std_logic;

begin

    U_TIMING : vga_timing
        generic map (
            H_VISIBLE => SCREEN_W,
            V_VISIBLE => SCREEN_H
        )
        port map (
            clk        => clk,
            rst        => rst,
            hsync      => hsync,
            vsync      => vsync,
            video_on   => video_on,
            pixel_x    => pixel_x,
            pixel_y    => pixel_y,
            pixel_tick => open
        );

    U_GAME : pong_game
        generic map (
            SCREEN_W     => SCREEN_W,
            SCREEN_H     => SCREEN_H,
            PADDLE_W     => PADDLE_W,
            PADDLE_H     => PADDLE_H,
            PADDLE_A_X   => PADDLE_A_X,
            PADDLE_B_X   => PADDLE_B_X,
            PADDLE_SPEED => PADDLE_SPEED,
            BALL_SIZE    => BALL_SIZE,
            BALL_SPEED   => BALL_SPEED,
            TICK_DIVISOR => TICK_DIVISOR,
            DEBOUNCE_LIM => DEBOUNCE_LIM,
            WIN_SCORE    => WIN_SCORE,
            WIN_MARGIN   => WIN_MARGIN
        )
        port map (
            clk            => clk,
            rst            => rst,
            btn_a_up_raw   => btn_a_up_raw,
            btn_a_down_raw => btn_a_down_raw,
            btn_b_up_raw   => btn_b_up_raw,
            btn_b_down_raw => btn_b_down_raw,
            ball_x         => ball_x,
            ball_y         => ball_y,
            paddle_a_y     => paddle_a_y,
            paddle_b_y     => paddle_b_y,
            score_a        => score_a,
            score_b        => score_b,
            game_over      => game_over,
            winner_is_a    => winner_is_a,
            game_tick_dbg  => open
        );

    U_RENDER : pong_render
        generic map (
            SCREEN_W   => SCREEN_W,
            SCREEN_H   => SCREEN_H,
            PADDLE_W   => PADDLE_W,
            PADDLE_H   => PADDLE_H,
            PADDLE_A_X => PADDLE_A_X,
            PADDLE_B_X => PADDLE_B_X,
            BALL_SIZE  => BALL_SIZE
        )
        port map (
            pixel_x    => pixel_x,
            pixel_y    => pixel_y,
            video_on   => video_on,
            ball_x     => ball_x,
            ball_y     => ball_y,
            paddle_a_y => paddle_a_y,
            paddle_b_y => paddle_b_y,
            vga_r      => render_r,
            vga_g      => render_g,
            vga_b      => render_b
        );

    -- ===== 分數拆位 =====
    a_tens_v <= (to_integer(score_a) / 10) mod 10;
    a_ones_v <= to_integer(score_a) mod 10;
    b_tens_v <= (to_integer(score_b) / 10) mod 10;
    b_ones_v <= to_integer(score_b) mod 10;

    -- to_unsigned(...)這種函式呼叫一樣不能直接塞進port map，先轉成獨立訊號
    digit_val_a_tens <= to_unsigned(a_tens_v, 4);
    digit_val_a_ones <= to_unsigned(a_ones_v, 4);
    digit_val_b_tens <= to_unsigned(b_tens_v, 4);
    digit_val_b_ones <= to_unsigned(b_ones_v, 4);

    -- ===== 4個數字框的絕對座標命中判斷（4個框y都一樣，共用一個rel_y）=====
    -- rel_x/rel_y 都先算成獨立訊號，port map只傳訊號名稱，不直接塞算式--
    -- Vivado不接受把複合運算式直接當port map的actual
    rel_y_score  <= pixel_y - SCORE_Y;
    rel_x_a_tens <= pixel_x - A_TENS_X;
    rel_x_a_ones <= pixel_x - A_ONES_X;
    rel_x_b_tens <= pixel_x - B_TENS_X;
    rel_x_b_ones <= pixel_x - B_ONES_X;

    in_a_tens_box <= '1' when (pixel_x >= A_TENS_X and pixel_x < A_TENS_X + DIGIT_W and
                                pixel_y >= SCORE_Y and pixel_y < SCORE_Y + DIGIT_H) else '0';
    in_a_ones_box <= '1' when (pixel_x >= A_ONES_X and pixel_x < A_ONES_X + DIGIT_W and
                                pixel_y >= SCORE_Y and pixel_y < SCORE_Y + DIGIT_H) else '0';
    in_b_tens_box <= '1' when (pixel_x >= B_TENS_X and pixel_x < B_TENS_X + DIGIT_W and
                                pixel_y >= SCORE_Y and pixel_y < SCORE_Y + DIGIT_H) else '0';
    in_b_ones_box <= '1' when (pixel_x >= B_ONES_X and pixel_x < B_ONES_X + DIGIT_W and
                                pixel_y >= SCORE_Y and pixel_y < SCORE_Y + DIGIT_H) else '0';

    U_DIGIT_A_TENS : digit_font
        generic map (DIGIT_W => DIGIT_W, DIGIT_H => DIGIT_H, SEG_T => SEG_T)
        port map (
            digit_value => digit_val_a_tens,
            rel_x       => rel_x_a_tens,
            rel_y       => rel_y_score,
            pixel_on    => a_tens_raw
        );

    U_DIGIT_A_ONES : digit_font
        generic map (DIGIT_W => DIGIT_W, DIGIT_H => DIGIT_H, SEG_T => SEG_T)
        port map (
            digit_value => digit_val_a_ones,
            rel_x       => rel_x_a_ones,
            rel_y       => rel_y_score,
            pixel_on    => a_ones_raw
        );

    U_DIGIT_B_TENS : digit_font
        generic map (DIGIT_W => DIGIT_W, DIGIT_H => DIGIT_H, SEG_T => SEG_T)
        port map (
            digit_value => digit_val_b_tens,
            rel_x       => rel_x_b_tens,
            rel_y       => rel_y_score,
            pixel_on    => b_tens_raw
        );

    U_DIGIT_B_ONES : digit_font
        generic map (DIGIT_W => DIGIT_W, DIGIT_H => DIGIT_H, SEG_T => SEG_T)
        port map (
            digit_value => digit_val_b_ones,
            rel_x       => rel_x_b_ones,
            rel_y       => rel_y_score,
            pixel_on    => b_ones_raw
        );

    a_tens_on <= a_tens_raw and in_a_tens_box;
    a_ones_on <= a_ones_raw and in_a_ones_box;
    b_tens_on <= b_tens_raw and in_b_tens_box;
    b_ones_on <= b_ones_raw and in_b_ones_box;

    digit_hit <= a_tens_on or a_ones_on or b_tens_on or b_ones_on;

    -- ===== WIN 三個字母：畫在贏家的分數格位置，A贏就在A_TENS_X、B贏就在
    --       B_TENS_X，Y座標跟分數數字共用同一個SCORE_Y/rel_y_score =====
    win_base_x <= A_TENS_X when winner_is_a = '1' else B_TENS_X;
    win_w_x    <= win_base_x;
    win_i_x    <= win_base_x + LETTER_W + LETTER_GAP;
    win_n_x    <= win_base_x + 2 * (LETTER_W + LETTER_GAP);

    rel_x_win_w <= pixel_x - win_w_x;
    rel_x_win_i <= pixel_x - win_i_x;
    rel_x_win_n <= pixel_x - win_n_x;

    in_win_w_box <= '1' when (pixel_x >= win_w_x and pixel_x < win_w_x + LETTER_W and
                               pixel_y >= SCORE_Y and pixel_y < SCORE_Y + LETTER_H) else '0';
    in_win_i_box <= '1' when (pixel_x >= win_i_x and pixel_x < win_i_x + LETTER_W and
                               pixel_y >= SCORE_Y and pixel_y < SCORE_Y + LETTER_H) else '0';
    in_win_n_box <= '1' when (pixel_x >= win_n_x and pixel_x < win_n_x + LETTER_W and
                               pixel_y >= SCORE_Y and pixel_y < SCORE_Y + LETTER_H) else '0';

    U_LETTER_W : letter_font
        generic map (LETTER_W => LETTER_W, LETTER_H => LETTER_H)
        port map (
            letter_sel => "00",
            rel_x      => rel_x_win_w,
            rel_y      => rel_y_score,
            pixel_on   => win_w_raw
        );

    U_LETTER_I : letter_font
        generic map (LETTER_W => LETTER_W, LETTER_H => LETTER_H)
        port map (
            letter_sel => "01",
            rel_x      => rel_x_win_i,
            rel_y      => rel_y_score,
            pixel_on   => win_i_raw
        );

    U_LETTER_N : letter_font
        generic map (LETTER_W => LETTER_W, LETTER_H => LETTER_H)
        port map (
            letter_sel => "10",
            rel_x      => rel_x_win_n,
            rel_y      => rel_y_score,
            pixel_on   => win_n_raw
        );

    win_w_on <= win_w_raw and in_win_w_box;
    win_i_on <= win_i_raw and in_win_i_box;
    win_n_on <= win_n_raw and in_win_n_box;

    win_hit <= win_w_on or win_i_on or win_n_on;

    -- ===== 贏家/輸家分數格分開判斷：贏球後，贏家那兩格被WIN字母取代，
    --       輸家那兩格維持顯示原本數字 =====
    winner_slots_hit <= (a_tens_on or a_ones_on) when winner_is_a = '1' else (b_tens_on or b_ones_on);
    loser_slots_hit  <= (b_tens_on or b_ones_on) when winner_is_a = '1' else (a_tens_on or a_ones_on);

    -- 平常(game_over='0')：四格數字都正常顯示；贏球後：輸家那兩格繼續顯示
    -- 數字，贏家那兩格改顯示WIN三個字母(winner_slots_hit不再參與，被win_hit取代)
    score_area_hit <= digit_hit when game_over = '0' else (loser_slots_hit or win_hit);

    -- ===== 最終輸出：分數區(含贏球後的WIN字樣)優先於球/球拍/背景，其餘交給
    --       pong_render自己的判斷(pong_render內部已經處理好video_on閘控，
    --       這裡不用再重複) =====
    vga_r <= "1111" when (score_area_hit = '1' and video_on = '1') else render_r;
    vga_g <= "1111" when (score_area_hit = '1' and video_on = '1') else render_g;
    vga_b <= "1111" when (score_area_hit = '1' and video_on = '1') else render_b;

end Behavioral;