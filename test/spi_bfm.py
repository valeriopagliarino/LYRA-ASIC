"""
Simple bit-banged driver matching spi_regfile.sv:
  * spi_cs   active-low chip select
  * spi_sck  passed through a 2-FF resynchronizer in the DUT, so it can
             be arbitrarily slow/asynchronous relative to `clk`
  * spi_mosi MSB-first, 16 bits, latched into config_reg on the 16th
             rising edge of spi_sck while spi_cs is held low

`set_bus_fn(sck, mosi, cs)` packs these three signals into wherever
they live on the DUT (in this project: bits [2:0] of uio_in).
"""

from cocotb.triggers import Timer


async def spi_write16(set_bus_fn, value, half_period_ns=200, idle_ns=200):
    """Shift a 16-bit value into spi_regfile, MSB first."""
    # Idle: CS inactive (high)
    set_bus_fn(sck=0, mosi=0, cs=1)
    await Timer(idle_ns, units="ns")

    # Assert CS
    set_bus_fn(sck=0, mosi=0, cs=0)
    await Timer(half_period_ns, units="ns")

    for i in range(15, -1, -1):
        bit = (value >> i) & 1
        set_bus_fn(sck=0, mosi=bit, cs=0)
        await Timer(half_period_ns, units="ns")
        set_bus_fn(sck=1, mosi=bit, cs=0)  # rising edge -> DUT samples mosi
        await Timer(half_period_ns, units="ns")
        set_bus_fn(sck=0, mosi=bit, cs=0)

    await Timer(half_period_ns, units="ns")
    # Deassert CS
    set_bus_fn(sck=0, mosi=0, cs=1)
    await Timer(idle_ns, units="ns")
