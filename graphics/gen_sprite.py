"""
gen_sprite.py  --  regenerate contested-chunk-0.png and contested-chunk-1.png

Two phase variants are required because the stripe period (STRIPE_SPACING_TILES)
is 64 tiles while a chunk is only 32 tiles, so the pattern shifts by half a period
every chunk.  Phase is selected in Lua by (cx - cy) % 2.

STRIPE_SPACING_TILES must be 32 or 64 (i.e. SIZE // STRIDE_SPACING_TILES in {1, 2}).

Requirements: Pillow  (pip install pillow)
Usage:        python gen_sprite.py
"""
from PIL import Image
import os

# -- Tuning knobs -----------------------------------------------------------
STRIPE_SPACING_TILES = 64    # tile period; must be 32 or 64
STRIPE_FILL          = 0.42  # fraction of period that is solid stripe
STRIPE_ALPHA         = 110   # 0-255; opacity of stripe pixels.
                             # NOTE: Factorio ignores tint.a on chart-mode draw_sprite,
                             # so opacity MUST be baked here, not set via STRIPE_COLOR.a.

# -- Derived ----------------------------------------------------------------
SIZE         = 2048                          # pixels; scale=0.5 -> 32x32 tile chunk
PERIOD_PX    = STRIPE_SPACING_TILES * 64    # 64 px per tile at this scale
HALF_W       = round(STRIPE_FILL * PERIOD_PX / 2)

assert STRIPE_SPACING_TILES in (32, 64), "only 32 or 64 are supported"
NUM_PHASES = PERIOD_PX // SIZE  # 1 for 32-tile period, 2 for 64-tile period

STRIPE_PIXEL = bytes([255, 255, 255, STRIPE_ALPHA])  # white; tinted yellow at runtime via STRIPE_COLOR.rgb

out_dir = os.path.dirname(os.path.abspath(__file__))

for phase in range(NUM_PHASES):
    phase_shift = phase * SIZE   # 0 for phase 0, 2048 for phase 1
    img_data    = bytearray(SIZE * SIZE * 4)

    for py in range(SIZE):
        v0        = (py + phase_shift) % PERIOD_PX
        row_start = py * SIZE * 4
        for px in range(SIZE):
            v = (v0 - px) % PERIOD_PX
            if v < HALF_W or v >= PERIOD_PX - HALF_W:
                i = row_start + px * 4
                img_data[i : i + 4] = STRIPE_PIXEL

    out = os.path.join(out_dir, f"contested-chunk-{phase}.png")
    img = Image.frombuffer("RGBA", (SIZE, SIZE), bytes(img_data), "raw", "RGBA", 0, 1)
    img.save(out, optimize=True)
    print(f"  phase {phase}: {os.path.getsize(out)//1024} KB  ->  {out}")

print(f"Done. spacing={STRIPE_SPACING_TILES} tiles  fill={STRIPE_FILL*100:.0f}%  phases={NUM_PHASES}")
