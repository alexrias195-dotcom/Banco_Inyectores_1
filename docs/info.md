## How it works

This project implements a 6-channel fuel injector sequencer and fuel pump relay controller driven by an input PWM signal on `ui_in[0]`. A synchronous 2-stage synchronizer samples `ui_in[0]` and measures its active duty cycle over a fixed window (`PWM_WIN_TICKS`) to map the signal into a level from `0` to `9` (`level_0_9`).

When a PWM signal is detected (`active_on = 1` and `rst_n = 1`), the fuel pump relay output (`uo_out[6]`) turns on and the 6-channel injector register (`uo_out[5:0]`) steps through channels `0` to `5` at a rate determined by `level_0_9`, asserting each channel pulse for `PULSE_TICKS` clock cycles. The current level (`0` to `9`) is also decoded to a 7-segment display on `uio_out[6:0]` with `uio_oe` set to `8'b0111_1111`.

## How to test

1. Assert `rst_n = 0` with `ena = 1` and `ui_in = 0`, then release `rst_n = 1` and confirm `uo_out` starts at `0` and `uio_oe` equals `8'h7F`.
2. Apply a PWM signal to `ui_in[0]` and let the measurement window advance so `active_on` asserts.
3. Verify that `uo_out[6]` (`RELAY_BOMBA`) activates, `uo_out[5:0]` (`INJ_0`..`INJ_5`) sequences across the 6 injector channels, and `uio_out[6:0]` updates the 7-segment output corresponding to `level_0_9`.

## External hardware

- PWM signal source connected to `ui_in[0]`.
- Power driver stages (transistors/MOSFETs with flyback diodes and/or relays for low-frequency bench testing) connected to `uo_out[5:0]` (6 injector channels) and `uo_out[6]` (fuel pump relay).
- 7-segment display connected to `uio_out[6:0]`.
