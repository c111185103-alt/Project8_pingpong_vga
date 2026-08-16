library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- VGA 640x480@60Hz 標準時序產生器 (可重複使用的獨立模組)。
--
-- pixel clock 標準規格是 25.175MHz，這裡用 100MHz/4=25MHz 簡化近似
-- (誤差約 0.7%，絕大多數螢幕都能同步顯示，教學專案常見做法，不用額外的
-- clock wizard 產生精確頻率)。
--
-- 所有時序常數都做成 generic，硬體用真正的 640x480 數字，模擬時可以
-- 換成很小的數字，不用真的跑滿一整個 800x525 才能驗證邏輯對不對。
--
-- 重要：block RAM 讀取本身有 1 個 clk 的延遲 (位址送進去，下一拍才有資料
-- 出來)，所以上層模組如果要接 blk_mem_gen，必須把這裡輸出的 hsync/vsync/
-- video_on 再額外延遲 1 拍，才能跟晚 1 拍出來的像素資料對齊，不然畫面會
-- 整體橫向偏移 1 個像素。這裡只負責產生「正確的時序基準」，對齊延遲的
-- 動作要在上層模組做。
entity vga_timing is
    generic (
        H_VISIBLE     : integer := 640;
        H_FRONT_PORCH : integer := 16;
        H_SYNC_PULSE  : integer := 96;
        H_BACK_PORCH  : integer := 48;
        V_VISIBLE     : integer := 480;
        V_FRONT_PORCH : integer := 10;
        V_SYNC_PULSE  : integer := 2;
        V_BACK_PORCH  : integer := 33;
        PIXEL_DIVISOR : integer := 4    -- 100MHz / PIXEL_DIVISOR = pixel clock，硬體固定4，模擬可縮小
    );
    port (
        clk        : in  std_logic;               -- 100MHz
        rst        : in  std_logic;
        hsync      : out std_logic;                -- 負極性 (脈衝期間為低電位)
        vsync      : out std_logic;                -- 負極性
        video_on   : out std_logic;                -- 目前是否在可視範圍內
        pixel_x    : out unsigned(15 downto 0);    -- 0~(H_VISIBLE-1)，只有 video_on='1' 時才有意義
        pixel_y    : out unsigned(15 downto 0);    -- 0~(V_VISIBLE-1)
        pixel_tick : out std_logic                 -- 每 PIXEL_DIVISOR 個 clk 拉高一拍，=pixel clock 的節拍
    );
end vga_timing;

architecture Behavioral of vga_timing is

    constant H_TOTAL : integer := H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    constant V_TOTAL : integer := V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    signal pixel_tick_i : std_logic := '0';
    signal h_cnt : integer range 0 to H_TOTAL - 1 := 0;
    signal v_cnt : integer range 0 to V_TOTAL - 1 := 0;

begin

    -- ===== Process 1：100MHz 除頻，產生 pixel clock 節拍 =====
    process(clk, rst)
        variable div_cnt : integer range 0 to PIXEL_DIVISOR - 1 := 0;
    begin
        if rst = '1' then
            div_cnt      := 0;
            pixel_tick_i <= '0';
        elsif rising_edge(clk) then
            if div_cnt = PIXEL_DIVISOR - 1 then
                div_cnt      := 0;
                pixel_tick_i <= '1';
            else
                div_cnt      := div_cnt + 1;
                pixel_tick_i <= '0';
            end if;
        end if;
    end process;

    pixel_tick <= pixel_tick_i;

    -- ===== Process 2：水平/垂直掃描計數器，只在 pixel_tick 那一拍才走一步 =====
    process(clk, rst)
    begin
        if rst = '1' then
            h_cnt <= 0;
            v_cnt <= 0;
        elsif rising_edge(clk) then
            if pixel_tick_i = '1' then
                if h_cnt = H_TOTAL - 1 then
                    h_cnt <= 0;
                    if v_cnt = V_TOTAL - 1 then
                        v_cnt <= 0;
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- ===== Process 3：由 h_cnt/v_cnt 解碼出 hsync/vsync/video_on (純組合邏輯) =====
    hsync <= '0' when (h_cnt >= H_VISIBLE + H_FRONT_PORCH) and
                       (h_cnt <  H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE)
             else '1';

    vsync <= '0' when (v_cnt >= V_VISIBLE + V_FRONT_PORCH) and
                       (v_cnt <  V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE)
             else '1';

    video_on <= '1' when (h_cnt < H_VISIBLE) and (v_cnt < V_VISIBLE) else '0';

    pixel_x <= to_unsigned(h_cnt, 16);
    pixel_y <= to_unsigned(v_cnt, 16);

end Behavioral;