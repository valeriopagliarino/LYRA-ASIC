# LYRA — Quad/Dual-Channel Audio DSP & ADAT Optical Interface ASIC

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![PDK](https://img.shields.io/badge/PDK-SkyWater_130nm-green.svg)

**LYRA** is an open-source audio processing ASIC designed for the **SkyWater 130nm (SKY130)** PDK. It integrates a dual-channel audio DSP, embedded programmable logic, multi-channel I2S audio interfaces, and a 4-channel optical ADAT encoder.

## Key Features

* **Silicon PDK:** SkyWater 130nm (SKY130)
* **DSP Engine:** 2-channel core for real-time audio filtering and processing
* **Programmable Logic:** On-chip configurable logic block for custom routing and hardware acceleration
* **Audio Inputs:** 4× Stereo I2S inputs (8 total channels, 16/24-bit @ 44.1/48 kHz)
* **Audio Outputs:** 2× Stereo I2S outputs (local monitoring) + 1× 4-channel optical ADAT output (TOSLINK)
* **System Clock:** 11.2896 MHz (256 × 44.1 kHz) single clock domain

## Specifications

| Parameter | Specification |
| :--- | :--- |
| **Process Node** | SkyWater 130nm (SKY130) |
| **System Clock** | 11.2896 MHz |
| **Audio Format** | 16-bit @ 44.1 kHz |
| **Inputs** | 4× Stereo I2S |
| **Outputs** | 2× Stereo I2S + 1× Optical ADAT (4 Ch) |
| **Target Flow** | OpenLane / Caravel |

## Project Structure

* `rtl/` — SystemVerilog source files (I2S, DSP, logic array, ADAT encoder, top wrapper)
* `tb/` — Testbenches and simulation files
* `openlane/` — Synthesis, placement, and routing configurations
* `docs/` — Architecture specs and timing documentation

## Quickstart

### Simulation

Run testbenches using Icarus Verilog or Verilator:

```bash
cd tb
make run_all
```

### ASIC Flow

Harden the top module using OpenLane:

```bash
make harden MODULE=lyra_top
```

## License

Copyright (c) 2026 Valerio Pagliarino.  
Licensed under the **Apache License, Version 2.0**.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
