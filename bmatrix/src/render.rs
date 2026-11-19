//! Software compositor: grid of cells -> BGRA pixel buffer.

use crate::atlas::Atlas;
use crate::config::{Blend, Config, Rgba};
use crate::sim::*;

#[derive(Clone, Copy, PartialEq)]
pub enum Mode {
    /// Fallback: topmost click-through layered window.
    Overlay,
    /// Opaque window: wallpaper layer of the desktop, or the screensaver.
    Opaque,
}

pub struct Renderer {
    pub main: Atlas,
    pub special: Atlas,
    pub mode: Mode,
    /// Wallpaper only (no windows). The glyphs are "cut out" of it, like the original.
    pub wallpaper: Option<Vec<u32>>,
    /// What each cell looked like when it was last painted (0 = empty). Only cells whose
    /// look changed are repainted, which is most of the CPU saving.
    pub cache: Vec<u64>,
    pub valid: bool,
    /// Cells repainted by the last `draw` (statistics for the debug log).
    pub repainted: usize,
}

fn scale(c: u8, k: u32) -> u32 {
    (c as u32 * k + 127) / 255
}

impl Renderer {
    /// Paints the rain into `buf`. With `full` (or on the first frame) the whole buffer is
    /// redrawn; otherwise `buf` must still hold the previous frame and only changed cells
    /// are repainted.
    pub fn draw(&mut self, cfg: &Config, sim: &Sim, buf: &mut [u32], w: usize, h: usize, full: bool) {
        let (cw, ch) = (self.main.cw, self.main.ch);
        let (x0, y0) = ((w - sim.cols * cw) / 2, (h - sim.rows * ch) / 2);

        let base = match self.mode {
            Mode::Overlay => {
                let a = cfg.overlay_opacity as u32;
                let (r, g, b) = if cfg.bg_bitmap { (0, 0, 0) } else { (cfg.bg.r, cfg.bg.g, cfg.bg.b) };
                (a << 24) | (scale(r, a) << 16) | (scale(g, a) << 8) | scale(b, a)
            }
            Mode::Opaque if cfg.bg_bitmap => 0xFF00_0000,
            Mode::Opaque => {
                0xFF00_0000 | ((cfg.bg.r as u32) << 16) | ((cfg.bg.g as u32) << 8) | cfg.bg.b as u32
            }
        };
        let full = full || !self.valid || self.cache.len() != sim.cells.len();
        self.repainted = if full { usize::MAX } else { 0 };
        if full {
            buf.fill(base);
            self.cache.clear();
            self.cache.resize(sim.cells.len(), 0);
        }

        let pick = |special: bool, head: bool| -> Rgba {
            match (special, head) {
                (false, true) => cfg.fg,
                (false, false) => cfg.fade,
                (true, true) => cfg.special_fg,
                (true, false) => cfg.special_fade,
            }
        };

        for row in 0..sim.rows {
            for col in 0..sim.cols {
                let idx = row * sim.cols + col;
                let cell = sim.cells[idx];
                let on = cell.flags & F_ON != 0;

                // The final colour of the cell (and with it its cache key).
                let mut color = Rgba { r: 0, g: 0, b: 0, a: 0 };
                let mut key = 0u64;
                if on {
                    let bright = cell.flags & (F_HEAD | F_FLASH) != 0;
                    color = pick(cell.flags & F_SPECIAL_STREAM != 0, bright);
                    // The trail fades out towards its end; the head keeps full brightness.
                    let slot = sim.slots.get(cell.sid as usize).copied().unwrap_or_default();
                    let age = (slot.head - row as i32).max(0) as f32;
                    let len = slot.len.max(1) as f32;
                    // 32 brightness steps: invisible to the eye, but a cell then only has to be
                    // repainted when its step changes, not on every move of its stream.
                    let fade = if bright {
                        1.0
                    } else {
                        let f = 0.12 + 0.88 * (1.0 - age / len).clamp(0.0, 1.0).powf(1.3);
                        (f * 32.0).round() / 32.0
                    };
                    let boost = if bright { cfg.head_brightness } else { 1.0 };
                    let shade = (cell.shade as f32 * fade * boost).min(255.0) as u32;
                    color.r = scale(color.r, shade) as u8;
                    color.g = scale(color.g, shade) as u8;
                    color.b = scale(color.b, shade) as u8;
                    if boost > 1.0 {
                        // Brighter than the configured colour: push it towards white.
                        let t = ((boost - 1.0) * 0.5).min(0.6);
                        let lift = |c: u8| (c as f32 + (255.0 - c as f32) * t) as u8;
                        color.r = lift(color.r);
                        color.g = lift(color.g);
                        color.b = lift(color.b);
                    }
                    key = 1u64
                        | ((cell.flags & F_SPECIAL_GLYPH != 0) as u64) << 1
                        | (cell.glyph as u64) << 2
                        | (color.r as u64) << 18
                        | (color.g as u64) << 26
                        | (color.b as u64) << 34
                        | (color.a as u64) << 42;
                }

                if self.cache[idx] == key {
                    continue; // looks exactly as it was painted last time
                }
                self.cache[idx] = key;
                if !full {
                    self.repainted += 1;
                }
                let (px, py) = (x0 + col * cw, y0 + row * ch);
                if !full {
                    for gy in 0..ch {
                        let o = (py + gy) * w + px;
                        buf[o..o + cw].fill(base);
                    }
                }
                if !on {
                    continue;
                }
                let atlas = if cell.flags & F_SPECIAL_GLYPH != 0 { &self.special } else { &self.main };
                let Some(mask) = atlas.glyphs.get(cell.glyph as usize) else { continue };
                for gy in 0..ch {
                    let o = (py + gy) * w + px;
                    let dst = &mut buf[o..o + cw];
                    let src = &mask[gy * atlas.cw..gy * atlas.cw + cw];
                    for (i, (d, &cov)) in dst.iter_mut().zip(src).enumerate() {
                        if cov == 0 {
                            continue;
                        }
                        let a = cov as u32 * color.a as u32 / 255;
                        let (r, g, b) = match &self.wallpaper {
                            Some(wp) => {
                                // Original blend: glyph colour combined with the wallpaper pixel,
                                // so the picture shows up as a different colour inside the rain.
                                let p = wp[o + i];
                                let (pr, pg, pb) = (
                                    scale((p >> 16) as u8, cov as u32),
                                    scale((p >> 8) as u8, cov as u32),
                                    scale(p as u8, cov as u32),
                                );
                                let (tr, tg, tb) = (scale(color.r, a), scale(color.g, a), scale(color.b, a));
                                match cfg.blend {
                                    Blend::Or => (tr | pr, tg | pg, tb | pb),
                                    Blend::And => (tr & pr.max(255 - a), tg & pg.max(255 - a), tb & pb.max(255 - a)),
                                    Blend::Xor => (tr ^ pr, tg ^ pg, tb ^ pb),
                                    Blend::Copy => (pr, pg, pb),
                                }
                            }
                            None => (scale(color.r, a), scale(color.g, a), scale(color.b, a)),
                        };
                        *d = match self.mode {
                            Mode::Overlay => {
                                let oa = a + cfg.overlay_opacity as u32 * (255 - a) / 255;
                                (oa << 24) | (r << 16) | (g << 8) | b
                            }
                            Mode::Opaque => 0xFF00_0000 | (r << 16) | (g << 8) | b,
                        };
                    }
                }
            }
        }
        self.valid = true;
    }
}
