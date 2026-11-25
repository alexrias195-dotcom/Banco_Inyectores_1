`default_nettype none

module tt_um_banco_inyectores #(
    parameter integer CLK_HZ = 50_000_000
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    localparam integer PWM_WIN_TICKS = CLK_HZ / 20;
    localparam integer PULSE_TICKS   = CLK_HZ / 50;

    wire       pwm_in;
    reg        pwm_ff1;
    reg        pwm_ff2;
    reg  [3:0] level_0_9;
    reg        active_on;

    reg  [5:0] inj_reg;
    reg  [2:0] ch_idx;
    reg  [25:0] period_cnt;
    reg  [25:0] pulse_cnt;

    reg  [25:0] high_cnt;
    reg  [25:0] win_cnt;
    reg  [3:0]  next_lvl;
    reg  [25:0] period_target;

    wire       relay_bomba;
    reg  [6:0] seg7;

    assign pwm_in = ui_in[0];
    assign uio_oe = 8'b0111_1111;

    // Medición de ciclo útil PWM en ventana fija y cálculo de nivel 0..9
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_ff1   <= 1'b0;
            pwm_ff2   <= 1'b0;
            level_0_9 <= 4'd0;
            active_on <= 1'b0;
            high_cnt  <= 26'd0;
            win_cnt   <= 26'd0;
        end else begin
            pwm_ff1 <= pwm_in;
            pwm_ff2 <= pwm_ff1;

            if (pwm_ff2) begin
                if (high_cnt < 26'd50_000_000) begin
                    high_cnt <= high_cnt + 26'd1;
                end
            end

            if (win_cnt >= (PWM_WIN_TICKS - 1)) begin
                if (high_cnt == 26'd0) begin
                    next_lvl  = 4'd0;
                    active_on <= 1'b0;
                end else begin
                    active_on <= 1'b1;
                    if (high_cnt >= ((PWM_WIN_TICKS * 9) / 10)) begin
                        next_lvl = 4'd9;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 8) / 10)) begin
                        next_lvl = 4'd8;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 7) / 10)) begin
                        next_lvl = 4'd7;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 6) / 10)) begin
                        next_lvl = 4'd6;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 5) / 10)) begin
                        next_lvl = 4'd5;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 4) / 10)) begin
                        next_lvl = 4'd4;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 3) / 10)) begin
                        next_lvl = 4'd3;
                    end else if (high_cnt >= ((PWM_WIN_TICKS * 2) / 10)) begin
                        next_lvl = 4'd2;
                    end else begin
                        next_lvl = 4'd1;
                    end
                end

                level_0_9 <= next_lvl;
                high_cnt  <= 26'd0;
                win_cnt   <= 26'd0;
            end else begin
                if (win_cnt < 26'd50_000_000) begin
                    win_cnt <= win_cnt + 26'd1;
                end
            end
        end
    end

    assign relay_bomba = (rst_n && active_on) ? 1'b1 : 1'b0;

    // Secuenciador de 6 canales según nivel detectado
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt <= 26'd0;
            pulse_cnt  <= 26'd0;
            ch_idx     <= 3'd0;
            inj_reg    <= 6'b000000;
        end else begin
            if (!active_on || (level_0_9 == 4'd0)) begin
                period_cnt <= 26'd0;
                pulse_cnt  <= 26'd0;
                ch_idx     <= 3'd0;
                inj_reg    <= 6'b000000;
            end else begin
                case (level_0_9)
                    4'd1:    period_target = CLK_HZ / 1;
                    4'd2:    period_target = CLK_HZ / 2;
                    4'd3:    period_target = CLK_HZ / 3;
                    4'd4:    period_target = CLK_HZ / 4;
                    4'd5:    period_target = CLK_HZ / 5;
                    4'd6:    period_target = CLK_HZ / 6;
                    4'd7:    period_target = CLK_HZ / 7;
                    4'd8:    period_target = CLK_HZ / 8;
                    default: period_target = CLK_HZ / 9;
                endcase

                if (period_target < (PULSE_TICKS + 10)) begin
                    period_target = PULSE_TICKS + 10;
                end

                if (period_cnt >= period_target) begin
                    period_cnt         <= 26'd0;
                    pulse_cnt          <= PULSE_TICKS[25:0];
                    inj_reg            <= 6'b000000;
                    inj_reg[ch_idx]    <= 1'b1;

                    if (ch_idx == 3'd5) begin
                        ch_idx <= 3'd0;
                    end else begin
                        ch_idx <= ch_idx + 3'd1;
                    end
                end else begin
                    period_cnt <= period_cnt + 26'd1;
                    if (pulse_cnt > 26'd0) begin
                        pulse_cnt <= pulse_cnt - 26'd1;
                    end else begin
                        inj_reg <= 6'b000000;
                    end
                end
            end
        end
    end

    assign uo_out = {1'b0, relay_bomba, inj_reg};

    // Decodificador de 7 segmentos (0..9)
    always @(*) begin
        case (level_0_9)
            4'd0:    seg7 = 7'b1000000;
            4'd1:    seg7 = 7'b1111001;
            4'd2:    seg7 = 7'b0100100;
            4'd3:    seg7 = 7'b0110000;
            4'd4:    seg7 = 7'b0011001;
            4'd5:    seg7 = 7'b0010010;
            4'd6:    seg7 = 7'b0000010;
            4'd7:    seg7 = 7'b0111000;
            4'd8:    seg7 = 7'b0000000;
            4'd9:    seg7 = 7'b0010000;
            default: seg7 = 7'b1000000;
        endcase
    end

    assign uio_out = {1'b0, seg7};

    // Evita advertencias por señales no usadas
    wire _unused = &{ena, uio_in, ui_in[7:1], 1'b0};

endmodule
