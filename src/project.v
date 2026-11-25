 library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tt_um_banco_inyectores is
    generic (
        CLK_HZ : integer := 50_000_000
    );
    port (
        ui_in   : in  std_logic_vector(7 downto 0);
        uo_out  : out std_logic_vector(7 downto 0);
        uio_in  : in  std_logic_vector(7 downto 0);
        uio_out : out std_logic_vector(7 downto 0);
        uio_oe  : out std_logic_vector(7 downto 0);
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end entity;

architecture rtl of tt_um_banco_inyectores is
    -- Constantes derivadas de la frecuencia del reloj (por defecto 50 MHz)
    constant PWM_WIN_TICKS : integer := CLK_HZ / 20; -- Ventana de medición de PWM (50 ms @ 50 MHz)
    constant PULSE_TICKS   : integer := CLK_HZ / 50; -- Duración de pulso por inyector (20 ms @ 50 MHz)

    -- Señales de sincronización y control
    signal pwm_in       : std_logic;
    signal pwm_ff1      : std_logic := '0';
    signal pwm_ff2      : std_logic := '0';
    signal level_0_9    : integer range 0 to 9 := 0;
    signal active_on    : std_logic := '0';

    -- Registro de 6 inyectores y secuencia
    signal inj_reg      : std_logic_vector(5 downto 0) := (others => '0');
    signal ch_idx       : integer range 0 to 5 := 0;
    signal period_cnt   : integer range 0 to 50_000_000 := 0;
    signal pulse_cnt    : integer range 0 to 50_000_000 := 0;

    -- Salidas auxiliares y display de 7 segmentos
    signal relay_bomba  : std_logic := '0';
    signal seg7         : std_logic_vector(6 downto 0) := "1000000";
    signal unused_sink  : std_logic;
begin

    -- Entradas y configuración de pines bidireccionales
    -- uio(6 downto 0) como salida (7 segmentos); uio(7) como entrada
    pwm_in      <= ui_in(0);
    uio_oe      <= "01111111";
    unused_sink <= ena or uio_in(7) or uio_in(0) or ui_in(1);

    -- ------------------------------------------------------------------------
    -- 1. Medición de señal PWM de entrada y cálculo de nivel (0 a 9)
    -- ------------------------------------------------------------------------
    process(clk, rst_n)
        variable high_cnt : integer range 0 to 50_000_000 := 0;
        variable win_cnt  : integer range 0 to 50_000_000 := 0;
        variable next_lvl : integer range 0 to 9;
    begin
        if rst_n = '0' then
            pwm_ff1   <= '0';
            pwm_ff2   <= '0';
            level_0_9 <= 0;
            active_on <= '0';
            high_cnt  := 0;
            win_cnt   := 0;
        elsif rising_edge(clk) then
            -- Sincronizador de 2 etapas para evitar metaestabilidad
            pwm_ff1 <= pwm_in;
            pwm_ff2 <= pwm_ff1;

            if pwm_ff2 = '1' then
                if high_cnt < 50_000_000 then
                    high_cnt := high_cnt + 1;
                end if;
            end if;

            if win_cnt >= PWM_WIN_TICKS - 1 then
                if high_cnt = 0 then
                    next_lvl  := 0;
                    active_on <= '0';
                else
                    active_on <= '1';
                    if high_cnt >= (PWM_WIN_TICKS * 9) / 10 then
                        next_lvl := 9;
                    elsif high_cnt >= (PWM_WIN_TICKS * 8) / 10 then
                        next_lvl := 8;
                    elsif high_cnt >= (PWM_WIN_TICKS * 7) / 10 then
                        next_lvl := 7;
                    elsif high_cnt >= (PWM_WIN_TICKS * 6) / 10 then
                        next_lvl := 6;
                    elsif high_cnt >= (PWM_WIN_TICKS * 5) / 10 then
                        next_lvl := 5;
                    elsif high_cnt >= (PWM_WIN_TICKS * 4) / 10 then
                        next_lvl := 4;
                    elsif high_cnt >= (PWM_WIN_TICKS * 3) / 10 then
                        next_lvl := 3;
                    elsif high_cnt >= (PWM_WIN_TICKS * 2) / 10 then
                        next_lvl := 2;
                    else
                        next_lvl := 1;
                    end if;
                end if;

                level_0_9 <= next_lvl;
                high_cnt  := 0;
                win_cnt   := 0;
            else
                if win_cnt < 50_000_000 then
                    win_cnt := win_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- Activación de relevador de bomba cuando hay señal PWM activa y reset inactivo
    relay_bomba <= '1' when (rst_n = '1' and active_on = '1') else '0';

    -- ------------------------------------------------------------------------
    -- 2. Secuenciador de 6 canales de inyectores
    -- ------------------------------------------------------------------------
    process(clk, rst_n)
        variable period_target : integer range 0 to 50_000_000;
    begin
        if rst_n = '0' then
            period_cnt <= 0;
            pulse_cnt  <= 0;
            ch_idx     <= 0;
            inj_reg    <= (others => '0');
        elsif rising_edge(clk) then
            if (active_on = '0') or (level_0_9 = 0) then
                period_cnt <= 0;
                pulse_cnt  <= 0;
                ch_idx     <= 0;
                inj_reg    <= (others => '0');
            else
                case level_0_9 is
                    when 1      => period_target := CLK_HZ / 1;
                    when 2      => period_target := CLK_HZ / 2;
                    when 3      => period_target := CLK_HZ / 3;
                    when 4      => period_target := CLK_HZ / 4;
                    when 5      => period_target := CLK_HZ / 5;
                    when 6      => period_target := CLK_HZ / 6;
                    when 7      => period_target := CLK_HZ / 7;
                    when 8      => period_target := CLK_HZ / 8;
                    when others => period_target := CLK_HZ / 9;
                end case;

                if period_target < (PULSE_TICKS + 10) then
                    period_target := PULSE_TICKS + 10;
                end if;

                if period_cnt >= period_target then
                    period_cnt      <= 0;
                    pulse_cnt       <= PULSE_TICKS;
                    inj_reg         <= (others => '0');
                    inj_reg(ch_idx) <= '1';

                    if ch_idx = 5 then
                        ch_idx <= 0;
                    else
                        ch_idx <= ch_idx + 1;
                    end if;
                else
                    period_cnt <= period_cnt + 1;
                    if pulse_cnt > 0 then
                        pulse_cnt <= pulse_cnt - 1;
                    else
                        inj_reg <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Salidas principales: uo_out(5 downto 0) inyectores, uo_out(6) bomba, uo_out(7) libre
    uo_out <= '0' & relay_bomba & inj_reg;

    -- ------------------------------------------------------------------------
    -- 3. Decodificador de 7 segmentos (nivel 0..9)
    -- ------------------------------------------------------------------------
    process(level_0_9)
    begin
        case level_0_9 is
            when 0      => seg7 <= "1000000";
            when 1      => seg7 <= "1111001";
            when 2      => seg7 <= "0100100";
            when 3      => seg7 <= "0110000";
            when 4      => seg7 <= "0011001";
            when 5      => seg7 <= "0010010";
            when 6      => seg7 <= "0000010";
            when 7      => seg7 <= "0111000";
            when 8      => seg7 <= "0000000";
            when 9      => seg7 <= "0010000";
            when others => seg7 <= "1000000";
        end case;
    end process;

    uio_out <= '0' & seg7;

end architecture;
