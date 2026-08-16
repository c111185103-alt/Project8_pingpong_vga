library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Project8：Atari Pong 核心遊戲邏輯（球的位置/方向、兩支球拍位置、
-- 碰撞判定、計分、發球/勝負FSM），純狀態運算，不含任何VGA像素輸出判斷--
-- 那部分留給另一個負責『畫面渲染』的模組去做，這裡只負責維護遊戲狀態。
--
-- 座標系統跟 vga_timing 的 pixel_x/pixel_y 共用同一個空間 (0~SCREEN_W-1,
-- 0~SCREEN_H-1)，方便渲染模組直接拿這裡輸出的座標去跟目前掃描到的
-- pixel_x/pixel_y 比對，判斷該不該畫球/球拍。
--
-- 跟 Project7 不同：這裡完全沒有牽涉到任何記憶體(BRAM)讀取，球/球拍/分數
-- 全部都是純暫存器，沒有『慢1拍』這種延遲問題要處理，渲染模組可以直接用
-- 組合邏輯拿這裡的輸出去跟 pixel_x/pixel_y 比較，不需要額外延遲對齊。
--
-- 遊戲節奏(game_tick)獨立於VGA像素時脈之外自己再除頻一次，跟畫面更新
-- 頻率脫鉤，方便日後想改遊戲節奏時不用動到VGA時序那一塊。
--
-- ===== 發球/勝負 FSM (跟 Project5 同一個精神，但規則細節不同) =====
-- S_WAIT_SERVE：球固定在正中央不動，等發球方按任一鍵(上或下)才出發，
--   球會朝對手方向飛出去。reset後預設由A方先發球。
-- S_PLAYING：球正常飛行、碰牆反彈、碰球拍反彈；漏接的一方，下一輪換
--   他重新發球(不是官方的每2分輪替制，是比照Project5「誰輸誰重發」)。
-- S_GAME_OVER：11分制、需淨勝2分才算贏（這個算式本身就涵蓋了平手要
--   多贏2分的情況，不需要另外寫deuce特殊分支）。一旦分出勝負就整個
--   定格，球/球拍都不再移動，直到下次rst才會重新開始。
entity pong_game is
    generic (
        SCREEN_W     : integer := 640;
        SCREEN_H     : integer := 480;
        PADDLE_W     : integer := 10;
        PADDLE_H     : integer := 60;
        PADDLE_A_X   : integer := 20;       -- A(左)方球拍固定X座標
        PADDLE_B_X   : integer := 610;      -- B(右)方球拍固定X座標
        PADDLE_SPEED : integer := 4;        -- 每次game_tick球拍移動的pixel數
        BALL_SIZE    : integer := 10;
        BALL_SPEED   : integer := 2;        -- 每次game_tick球移動的pixel數(固定值，不隨遊戲進行變速)
        TICK_DIVISOR : integer := 1000000;  -- 100MHz除到約100Hz的遊戲節奏
        DEBOUNCE_LIM : integer := 1_000_000; -- 按鍵去彈跳長度，跟Project5/6同一個慣例，模擬時建議改小
        WIN_SCORE    : integer := 11;       -- 至少要達到這個分數才有機會贏
        WIN_MARGIN   : integer := 2         -- 而且要淨勝對手這麼多分
    );
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        btn_a_up_raw   : in  std_logic;   -- 原始、未去彈跳訊號，去彈跳在這個模組內部做
        btn_a_down_raw : in  std_logic;
        btn_b_up_raw   : in  std_logic;
        btn_b_down_raw : in  std_logic;

        ball_x     : out unsigned(15 downto 0);
        ball_y     : out unsigned(15 downto 0);
        paddle_a_y : out unsigned(15 downto 0);
        paddle_b_y : out unsigned(15 downto 0);
        score_a    : out unsigned(7 downto 0);
        score_b    : out unsigned(7 downto 0);

        game_over   : out std_logic;  -- '1'代表已經分出勝負、畫面定格中
        winner_is_a : out std_logic;  -- 只有 game_over='1' 時才有意義；'1'=A贏，'0'=B贏

        game_tick_dbg : out std_logic  -- 純模擬觀察用，不接實體接腳
    );
end pong_game;

architecture Behavioral of pong_game is

    -- 跟 Project5/6 同一份 debounce.vhd 沿用，介面完全比照 pingpong_top.vhd
    -- 裡的宣告方式
    component debounce is
        generic (
            DEBOUNCE_LIMIT : integer := 1_000_000
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            btn_in    : in  std_logic;
            btn_out   : out std_logic;
            btn_level : out std_logic
        );
    end component;

    -- 球拍要「按住持續移動」，所以接 btn_level(持續電位)，不是 btn_out(單脈波)--
    -- 這點跟 Project6 的 GRST/SW0 是同一個接法，跟它的擊球鍵(單脈波判定)不同
    signal btn_a_up_db, btn_a_down_db, btn_b_up_db, btn_b_down_db : std_logic;

    signal tick_cnt  : integer range 0 to TICK_DIVISOR - 1 := 0;
    signal game_tick : std_logic := '0';

    type game_state_t is (S_WAIT_SERVE, S_PLAYING, S_GAME_OVER);
    signal state         : game_state_t := S_WAIT_SERVE;
    signal serving_a     : std_logic := '1';  -- '1'=輪到A發球，'0'=輪到B發球；reset後預設A
    signal game_over_i   : std_logic := '0';
    signal winner_is_a_i : std_logic := '0';

    signal ball_x_i, ball_y_i         : unsigned(15 downto 0);
    signal ball_dir_right              : std_logic := '1';  -- 1=往右(B方向)，0=往左(A方向)
    signal ball_dir_down               : std_logic := '1';  -- 1=往下，0=往上

    signal paddle_a_y_i, paddle_b_y_i : unsigned(15 downto 0);
    signal score_a_i, score_b_i       : unsigned(7 downto 0);

    -- 8-bit LFSR，跟 Project6 同一個多項式 (x^8+x^6+x^5+x^4+1)，但這裡不是
    -- 拿來選速度，是在球拍反彈的瞬間拿最低1個bit決定要不要順便翻轉垂直
    -- 方向，讓反彈角度有隨機性，不是每次都以固定角度彈回去。
    signal lfsr          : std_logic_vector(7 downto 0) := "10101010"; -- 種子不可為全0
    signal lfsr_feedback : std_logic;

begin

    lfsr_feedback <= lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3);

    -- ===== 4 顆球拍按鍵各自去彈跳，只接 btn_level，btn_out 不用留 open =====
    U_DB_A_UP : debounce
        generic map (DEBOUNCE_LIMIT => DEBOUNCE_LIM)
        port map (clk => clk, rst => rst, btn_in => btn_a_up_raw, btn_out => open, btn_level => btn_a_up_db);

    U_DB_A_DOWN : debounce
        generic map (DEBOUNCE_LIMIT => DEBOUNCE_LIM)
        port map (clk => clk, rst => rst, btn_in => btn_a_down_raw, btn_out => open, btn_level => btn_a_down_db);

    U_DB_B_UP : debounce
        generic map (DEBOUNCE_LIMIT => DEBOUNCE_LIM)
        port map (clk => clk, rst => rst, btn_in => btn_b_up_raw, btn_out => open, btn_level => btn_b_up_db);

    U_DB_B_DOWN : debounce
        generic map (DEBOUNCE_LIMIT => DEBOUNCE_LIM)
        port map (clk => clk, rst => rst, btn_in => btn_b_down_raw, btn_out => open, btn_level => btn_b_down_db);

    -- ===== Process 1：game_tick 產生器，100MHz除頻成遊戲節奏 =====
    process(clk, rst)
    begin
        if rst = '1' then
            tick_cnt  <= 0;
            game_tick <= '0';
        elsif rising_edge(clk) then
            if tick_cnt = TICK_DIVISOR - 1 then
                tick_cnt  <= 0;
                game_tick <= '1';
            else
                tick_cnt  <= tick_cnt + 1;
                game_tick <= '0';
            end if;
        end if;
    end process;

    game_tick_dbg <= game_tick;

    -- ===== Process 2：LFSR 位移，每個 game_tick 動一次 =====
    process(clk, rst)
    begin
        if rst = '1' then
            lfsr <= "10101010";
        elsif rising_edge(clk) then
            if game_tick = '1' then
                lfsr <= lfsr(6 downto 0) & lfsr_feedback;
            end if;
        end if;
    end process;

    -- ===== Process 3：兩支球拍移動，A、B 各自獨立、上下夾在畫面範圍內。
    --       S_GAME_OVER 時整個鎖住不動，其餘狀態(含等待發球)都可以調整位置 =====
    process(clk, rst)
    begin
        if rst = '1' then
            paddle_a_y_i <= to_unsigned((SCREEN_H - PADDLE_H) / 2, 16);
            paddle_b_y_i <= to_unsigned((SCREEN_H - PADDLE_H) / 2, 16);
        elsif rising_edge(clk) then
            if game_tick = '1' and state /= S_GAME_OVER then
                -- 邊界用明確clamp，不是只靠減法前的guard擋住--否則PADDLE_SPEED
                -- 除不盡邊界距離時，球拍會卡在離邊界還差一截的地方，永遠到不了
                -- 剛好0或剛好(SCREEN_H-PADDLE_H)
                if btn_a_up_db = '1' then
                    if paddle_a_y_i >= PADDLE_SPEED then
                        paddle_a_y_i <= paddle_a_y_i - PADDLE_SPEED;
                    else
                        paddle_a_y_i <= (others => '0');
                    end if;
                elsif btn_a_down_db = '1' then
                    if paddle_a_y_i <= (SCREEN_H - PADDLE_H - PADDLE_SPEED) then
                        paddle_a_y_i <= paddle_a_y_i + PADDLE_SPEED;
                    else
                        paddle_a_y_i <= to_unsigned(SCREEN_H - PADDLE_H, 16);
                    end if;
                end if;

                if btn_b_up_db = '1' then
                    if paddle_b_y_i >= PADDLE_SPEED then
                        paddle_b_y_i <= paddle_b_y_i - PADDLE_SPEED;
                    else
                        paddle_b_y_i <= (others => '0');
                    end if;
                elsif btn_b_down_db = '1' then
                    if paddle_b_y_i <= (SCREEN_H - PADDLE_H - PADDLE_SPEED) then
                        paddle_b_y_i <= paddle_b_y_i + PADDLE_SPEED;
                    else
                        paddle_b_y_i <= to_unsigned(SCREEN_H - PADDLE_H, 16);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ===== Process 4：發球/勝負 FSM + 球的移動、邊界/球拍碰撞判定、計分 =====
    -- 碰撞檢查刻意加上方向判斷(ball_dir_right='0'/'1')才觸發，避免球剛從
    -- 球拍彈開、往反方向離開時，位置剛好還在判定區間內卻誤觸發二次碰撞。
    process(clk, rst)
        variable next_x     : integer;
        variable next_y     : integer;
        variable hit_paddle : boolean;
    begin
        if rst = '1' then
            ball_x_i       <= to_unsigned(PADDLE_A_X + PADDLE_W, 16);  -- 預設A發球，球停在A板旁邊
            ball_y_i       <= to_unsigned(SCREEN_H / 2, 16);
            ball_dir_right <= '1';
            ball_dir_down  <= '1';
            score_a_i      <= (others => '0');
            score_b_i      <= (others => '0');
            state          <= S_WAIT_SERVE;
            serving_a      <= '1';
            game_over_i    <= '0';
            winner_is_a_i  <= '0';
        elsif rising_edge(clk) then
            if game_tick = '1' then

                case state is

                    when S_WAIT_SERVE =>
                        -- 球停在發球方球拍旁邊、垂直位置固定在
                        -- SCREEN_H/2，方向鎖定朝向對手；發球方要按鍵(表示準備好了)
                        -- 且球拍要真的碰到球(球拍範圍跟球的垂直位置重疊，公式跟S_PLAYING那邊的碰撞判定一樣)
                        -- 才會真正出發--球拍還沒移動到球所在的高度時，光按鍵不會發球，要先把球拍移過去
                        ball_y_i      <= to_unsigned(SCREEN_H / 2, 16);
                        ball_dir_down <= '1';
                        if serving_a = '1' then
                            ball_x_i       <= to_unsigned(PADDLE_A_X + PADDLE_W, 16);  -- 停在A板右邊
                            ball_dir_right <= '1';  -- A發球，朝右(B方向)出擊
                            if (btn_a_up_db = '1' or btn_a_down_db = '1') and
                               (SCREEN_H / 2 + BALL_SIZE >= to_integer(paddle_a_y_i)) and
                               (SCREEN_H / 2 <= to_integer(paddle_a_y_i) + PADDLE_H) then
                                state <= S_PLAYING;
                            end if;
                        else
                            ball_x_i       <= to_unsigned(PADDLE_B_X - BALL_SIZE, 16);  -- 停在B板左邊
                            ball_dir_right <= '0';  -- B發球，朝左(A方向)出擊
                            if (btn_b_up_db = '1' or btn_b_down_db = '1') and
                               (SCREEN_H / 2 + BALL_SIZE >= to_integer(paddle_b_y_i)) and
                               (SCREEN_H / 2 <= to_integer(paddle_b_y_i) + PADDLE_H) then
                                state <= S_PLAYING;
                            end if;
                        end if;

                    when S_PLAYING =>
                        if ball_dir_right = '1' then
                            next_x := to_integer(ball_x_i) + BALL_SPEED;
                        else
                            next_x := to_integer(ball_x_i) - BALL_SPEED;
                        end if;

                        if ball_dir_down = '1' then
                            next_y := to_integer(ball_y_i) + BALL_SPEED;
                        else
                            next_y := to_integer(ball_y_i) - BALL_SPEED;
                        end if;

                        -- 上下邊界反彈
                        if next_y <= 0 then
                            next_y        := 0;
                            ball_dir_down <= '1';
                        elsif next_y >= SCREEN_H - BALL_SIZE then
                            next_y        := SCREEN_H - BALL_SIZE;
                            ball_dir_down <= '0';
                        end if;

                        -- 左側：往左飛、快到A方球拍那一列
                        if ball_dir_right = '0' and next_x <= PADDLE_A_X + PADDLE_W then
                            hit_paddle := (to_integer(ball_y_i) + BALL_SIZE >= to_integer(paddle_a_y_i)) and
                                          (to_integer(ball_y_i) <= to_integer(paddle_a_y_i) + PADDLE_H);
                            if hit_paddle then
                                next_x         := PADDLE_A_X + PADDLE_W;
                                ball_dir_right <= '1';
                                if lfsr(0) = '1' then
                                    ball_dir_down <= not ball_dir_down;
                                end if;
                            else
                                -- A沒接到，B得1分；A是輸家，下一輪換A重新發球，
                                -- 球直接跳到A板旁邊等待(不是螢幕正中央)
                                score_b_i <= score_b_i + 1;
                                serving_a <= '1';
                                next_x    := PADDLE_A_X + PADDLE_W;
                                next_y    := SCREEN_H / 2;
                                if (score_b_i + 1 >= WIN_SCORE) and (score_b_i + 1 >= score_a_i + WIN_MARGIN) then
                                    state         <= S_GAME_OVER;
                                    game_over_i   <= '1';
                                    winner_is_a_i <= '0';
                                else
                                    state <= S_WAIT_SERVE;
                                end if;
                            end if;

                        -- 右側：往右飛、快到B方球拍那一列
                        elsif ball_dir_right = '1' and next_x >= PADDLE_B_X - BALL_SIZE then
                            hit_paddle := (to_integer(ball_y_i) + BALL_SIZE >= to_integer(paddle_b_y_i)) and
                                          (to_integer(ball_y_i) <= to_integer(paddle_b_y_i) + PADDLE_H);
                            if hit_paddle then
                                next_x         := PADDLE_B_X - BALL_SIZE;
                                ball_dir_right <= '0';
                                if lfsr(0) = '1' then
                                    ball_dir_down <= not ball_dir_down;
                                end if;
                            else
                                -- B沒接到，A得1分；B是輸家，下一輪換B重新發球，
                                -- 球直接跳到B板旁邊等待(不是螢幕正中央)
                                score_a_i <= score_a_i + 1;
                                serving_a <= '0';
                                next_x    := PADDLE_B_X - BALL_SIZE;
                                next_y    := SCREEN_H / 2;
                                if (score_a_i + 1 >= WIN_SCORE) and (score_a_i + 1 >= score_b_i + WIN_MARGIN) then
                                    state         <= S_GAME_OVER;
                                    game_over_i   <= '1';
                                    winner_is_a_i <= '1';
                                else
                                    state <= S_WAIT_SERVE;
                                end if;
                            end if;
                        end if;

                        ball_x_i <= to_unsigned(next_x, 16);
                        ball_y_i <= to_unsigned(next_y, 16);

                    when S_GAME_OVER =>
                        null;  -- 整個定格，球/分數都不再變化，直到下次rst

                end case;

            end if;
        end if;
    end process;

    ball_x      <= ball_x_i;
    ball_y      <= ball_y_i;
    paddle_a_y  <= paddle_a_y_i;
    paddle_b_y  <= paddle_b_y_i;
    score_a     <= score_a_i;
    score_b     <= score_b_i;
    game_over   <= game_over_i;
    winner_is_a <= winner_is_a_i;

end Behavioral;