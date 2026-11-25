# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start banco de inyectores test")

    # Reloj de 50 MHz (periodo de 20 ns)
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset activo en bajo
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    assert int(dut.uo_out.value) == 0, "uo_out debe ser 0 durante reset"

    # Liberar reset y verificar configuracion de pines bidireccionales
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    assert int(dut.uio_oe.value) == 0x7F, (
        f"uio_oe esperado 0x7F, obtenido {hex(int(dut.uio_oe.value))}"
    )

    # Con ui_in[0] = 0, no debe haber activacion de bomba ni inyectores
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 200)
    assert int(dut.uo_out.value) == 0, "Sin senal PWM, uo_out debe mantenerse en 0"

    # Simular senal PWM activa en ui_in[0] con ciclos alternados
    dut._log.info("Probando senal PWM en ui_in[0]")
    for _ in range(100):
        dut.ui_in.value = 1
        await ClockCycles(dut.clk, 150)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 150)

    # Verificar que las salidas no tengan bits indefinidos (X/Z)
    uo_str = str(dut.uo_out.value)
    uio_str = str(dut.uio_out.value)
    assert "x" not in uo_str.lower() and "z" not in uo_str.lower(), (
        f"uo_out contiene bits X/Z: {uo_str}"
    )
    assert "x" not in uio_str.lower() and "z" not in uio_str.lower(), (
        f"uio_out contiene bits X/Z: {uio_str}"
    )

    dut._log.info(f"uo_out final: {dut.uo_out.value}, uio_out final: {dut.uio_out.value}")
