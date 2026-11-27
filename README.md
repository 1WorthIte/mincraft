# Mincraft — modular Verilog source

These 12 files were split from the uploaded working `vga_demo.v`. Module bodies are preserved verbatim; only standalone `default_nettype` directives were added around each file.

## Quartus setup

1. Back up your existing `vga_demo.v`. **Remove the old monolithic `vga_demo.v` from the Quartus project** before adding these files, or you will get duplicate module definitions.
2. Copy the 12 `.v` files into your project source directory.
3. In Quartus, go to **Project > Add/Remove Files in Project** and add all 12 `.v` files.
4. Keep the top-level entity as `vga_demo`.
5. Keep all existing support files, including `vga_adapter`, `object_mem`, your `.mif`/`.hex` assets, `.qsf` pin assignments, and other project dependencies. These are NOT bundled here.
6. Run **Processing > Start > Start Analysis & Synthesis**, then compile/program as usual.

## Files

| File | Responsibility |
|---|---|
| `vga_demo.v` | Top-level wiring, keyboard input, game and redraw control, VGA mux |
| `block_map.v` | Mutable world tiles and block reads/writes |
| `world.v` | World tile/texture renderer |
| `steve.v` | Player physics, sprite rendering and animation |
| `block_selector.v` | Index-to-target coordinate mapping |
| `selection_ui.v` | Selection borders and highlighted target |
| `block_interaction.v` | Block placement, mining timer and progress |
| `mining_bar.v` | Mining progress bar framebuffer painter |
| `sync.v` | Input synchronizer |
| `regn.v` | Parameterized register |
| `upDn_count.v` | Parameterized up/down counter |
| `hex7seg.v` | Seven-segment decoder |

No modules were renamed or altered internally. This is a file-organization refactor, not a functional redesign. Quartus compilation and hardware verification have not been performed here.
