#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
rust = root / "wgpu-verify/src/bin/noir_winit_host.rs"
racket = root / "noir/ui/main.rkt"
placement = root / "wgpu-verify/src/host_placement.wgsl"
legacy = root / "wgpu-verify/src/host_text.wgsl"

atlas_code = r'''fn write_atlas(patterns: &[[u8; 7]]) -> Vec<u8> {
    let mut pixels = vec![0u8; (ATLAS_WIDTH * ATLAS_HEIGHT) as usize];
    for (glyph, rows) in patterns.iter().enumerate() {
        for (row, bits) in rows.iter().enumerate() {
            for column in 0..5u32 {
                if bits & (1 << (4 - column)) != 0 {
                    let x = glyph as u32 * ATLAS_GLYPH_WIDTH + 1 + column;
                    let y = row as u32;
                    pixels[(y * ATLAS_WIDTH + x) as usize] = 255;
                }
            }
        }
    }
    pixels
}

fn digit_atlas_pixels() -> Vec<u8> {
    let patterns: [[u8; 7]; 10] = [
        [0b01110,0b10001,0b10011,0b10101,0b11001,0b10001,0b01110],
        [0b00100,0b01100,0b00100,0b00100,0b00100,0b00100,0b01110],
        [0b01110,0b10001,0b00001,0b00010,0b00100,0b01000,0b11111],
        [0b11110,0b00001,0b00001,0b01110,0b00001,0b00001,0b11110],
        [0b00010,0b00110,0b01010,0b10010,0b11111,0b00010,0b00010],
        [0b11111,0b10000,0b10000,0b11110,0b00001,0b00001,0b11110],
        [0b01110,0b10000,0b10000,0b11110,0b10001,0b10001,0b01110],
        [0b11111,0b00001,0b00010,0b00100,0b01000,0b01000,0b01000],
        [0b01110,0b10001,0b10001,0b01110,0b10001,0b10001,0b01110],
        [0b01110,0b10001,0b10001,0b01111,0b00001,0b00001,0b01110],
    ];
    write_atlas(&patterns)
}

fn ascii_atlas_pixels() -> Vec<u8> {
    let patterns: [[u8; 7]; 27] = [
        [0,0,0,0,0,0,0],
        [0b01110,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
        [0b11110,0b10001,0b10001,0b11110,0b10001,0b10001,0b11110],
        [0b01110,0b10001,0b10000,0b10000,0b10000,0b10001,0b01110],
        [0b11110,0b10001,0b10001,0b10001,0b10001,0b10001,0b11110],
        [0b11111,0b10000,0b10000,0b11110,0b10000,0b10000,0b11111],
        [0b11111,0b10000,0b10000,0b11110,0b10000,0b10000,0b10000],
        [0b01110,0b10001,0b10000,0b10111,0b10001,0b10001,0b01110],
        [0b10001,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
        [0b01110,0b00100,0b00100,0b00100,0b00100,0b00100,0b01110],
        [0b00001,0b00001,0b00001,0b00001,0b10001,0b10001,0b01110],
        [0b10001,0b10010,0b10100,0b11000,0b10100,0b10010,0b10001],
        [0b10000,0b10000,0b10000,0b10000,0b10000,0b10000,0b11111],
        [0b10001,0b11011,0b10101,0b10101,0b10001,0b10001,0b10001],
        [0b10001,0b11001,0b10101,0b10011,0b10001,0b10001,0b10001],
        [0b01110,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
        [0b11110,0b10001,0b10001,0b11110,0b10000,0b10000,0b10000],
        [0b01110,0b10001,0b10001,0b10001,0b10101,0b10010,0b01101],
        [0b11110,0b10001,0b10001,0b11110,0b10100,0b10010,0b10001],
        [0b01111,0b10000,0b10000,0b01110,0b00001,0b00001,0b11110],
        [0b11111,0b00100,0b00100,0b00100,0b00100,0b00100,0b00100],
        [0b10001,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
        [0b10001,0b10001,0b10001,0b10001,0b10001,0b01010,0b00100],
        [0b10001,0b10001,0b10001,0b10101,0b10101,0b10101,0b01010],
        [0b10001,0b10001,0b01010,0b00100,0b01010,0b10001,0b10001],
        [0b10001,0b10001,0b01010,0b00100,0b00100,0b00100,0b00100],
        [0b11111,0b00001,0b00010,0b00100,0b01000,0b10000,0b11111],
    ];
    write_atlas(&patterns)
}
'''

text = rust.read_text()
pattern = r"fn digit_atlas_pixels\(\)->Vec<u8>\{.*?\nfn main\(\) -> Result<\(\)> \{"
replacement = atlas_code + "\nfn main() -> Result<()> {"
new_text, count = re.subn(pattern, replacement, text, flags=re.S)
if count != 1:
    raise SystemExit(f"expected one atlas block, replaced {count}")
rust.write_text(new_text)

text = racket.read_text()
text = text.replace("(/ 3.0 162.0)\n            (/ 5.0 8.0)", "(/ 5.0 162.0)\n            (/ 7.0 8.0)")
racket.write_text(text)

text = placement.read_text()
text = text.replace("3.0 / ATLAS_WIDTH,\n      5.0 / ATLAS_HEIGHT,", "5.0 / ATLAS_WIDTH,\n      7.0 / ATLAS_HEIGHT,")
placement.write_text(text)

text = legacy.read_text()
text = text.replace("vec2<f32>(3.0, 5.0)", "vec2<f32>(5.0, 7.0)")
legacy.write_text(text)
