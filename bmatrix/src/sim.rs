//! Matrix stream simulation (columns of falling characters).

pub const F_ON: u8 = 1;
pub const F_HEAD: u8 = 2;
pub const F_SPECIAL_STREAM: u8 = 4;
pub const F_SPECIAL_GLYPH: u8 = 8;
/// Short flash of a trail character (drawn with the head colour for one frame).
pub const F_FLASH: u8 = 16;

#[derive(Clone, Copy)]
pub struct Cell {
    pub glyph: u16,
    pub flags: u8,
    /// Per-stream brightness (depth effect), 0..=255.
    pub shade: u8,
    /// Slot of the stream that drew this cell (index into `Sim::slots`).
    pub sid: u16,
}

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed | 1)
    }
    pub fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    pub fn below(&mut self, n: usize) -> usize {
        if n == 0 {
            0
        } else {
            ((self.next() >> 11) % n as u64) as usize
        }
    }
    pub fn unit(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
}

pub struct SimParams {
    pub max_stream: usize,
    pub speed_variance: f32,
    pub monotonous: bool,
    pub back_trace: i32,
    pub randomized: bool,
    pub leading: i32,
    pub space_pad: i32,
    pub refresh_ms: f32,
    pub special_probability: f32,
    /// Share of time a column carries a stream (rain density), 0-1.
    pub spawn_rate: f32,
    /// Flicker strength, 0-1.
    pub flicker: f32,
    /// Chance per frame that a stream's head symbol changes, 0-1.
    pub head_flicker: f32,
    /// Trail length range in rows when monotonous cleanup is off; `trail_max` 0 = automatic.
    pub trail_min: i32,
    pub trail_max: i32,
    pub charset_len: usize,
    /// Special strings as indices into the special glyph atlas.
    pub special_strings: Vec<Vec<u16>>,
}

/// Head position and trail length of a stream, looked up by the renderer through `Cell::sid`.
#[derive(Clone, Copy, Default)]
pub struct Slot {
    pub head: i32,
    pub len: i32,
}

struct Stream {
    col: usize,
    slot: u16,
    head: i32,
    /// Trail length in rows; rows further behind the head are erased.
    len: i32,
    speed: f32,
    shade: u8,
    acc: f32,
    special: Option<(usize, i32)>,
    /// True while this stream is the one running down its column.
    owns_col: bool,
}

pub struct Sim {
    pub cols: usize,
    pub rows: usize,
    pub cells: Vec<Cell>,
    pub slots: Vec<Slot>,
    free_slots: Vec<u16>,
    streams: Vec<Stream>,
    occupied: Vec<bool>,
    rng: Rng,
    p: SimParams,
}

const EMPTY: Cell = Cell { glyph: 0, flags: 0, shade: 0, sid: 0 };

impl Sim {
    pub fn new(cols: usize, rows: usize, p: SimParams, seed: u64) -> Sim {
        Sim {
            cols,
            rows,
            cells: vec![EMPTY; cols * rows],
            slots: Vec::new(),
            free_slots: Vec::new(),
            streams: Vec::new(),
            occupied: vec![false; cols],
            rng: Rng::new(seed),
            p,
        }
    }

    /// Erases a cell only if it still belongs to the given stream.
    fn clear_own(&mut self, col: usize, row: i32, sid: u16) {
        if row >= 0 && (row as usize) < self.rows {
            let cell = &mut self.cells[row as usize * self.cols + col];
            if cell.flags != 0 && cell.sid == sid {
                *cell = EMPTY;
            }
        }
    }

    fn spawn(&mut self, dt_ms: f32) {
        let rows = self.rows as i32;
        let d = self.p.spawn_rate.clamp(0.01, 0.97);
        // Trail length range. Denser rain also gets longer streams by default.
        let auto_max = ((rows as f32 * (0.3 + 0.5 * d)) as i32).max(12);
        let tmax = if self.p.trail_max > 0 { self.p.trail_max } else { auto_max }.max(3);
        let tmin = self.p.trail_min.clamp(2, tmax);
        let avg_speed = (1.0 + self.p.speed_variance) / 2.0;
        // A column is "busy" while the head of its stream is on screen; after that the next
        // stream may start while the old trail is still fading out below.
        let head_ms = (rows as f32 * self.p.refresh_ms / avg_speed).max(1.0);
        let rate = d / ((1.0 - d) * head_ms); // starts per ms of a free column
        let chance = 1.0 - (-rate * dt_ms).exp();

        for col in 0..self.cols {
            if self.streams.len() >= self.p.max_stream {
                break;
            }
            if self.occupied[col] || self.rng.unit() > chance {
                continue;
            }
            let slot = match self.free_slots.pop() {
                Some(s) => s,
                None => {
                    if self.slots.len() >= u16::MAX as usize {
                        break;
                    }
                    self.slots.push(Slot::default());
                    (self.slots.len() - 1) as u16
                }
            };
            self.occupied[col] = true;
            let special = if !self.p.special_strings.is_empty()
                && self.rng.unit() < self.p.special_probability
            {
                let idx = self.rng.below(self.p.special_strings.len());
                let len = self.p.special_strings[idx].len() as i32;
                let room = (rows - len).max(1) as usize;
                Some((idx, self.rng.below(room) as i32))
            } else {
                None
            };
            let sv = self.p.speed_variance;
            let speed = 1.0 + self.rng.unit() * (sv - 1.0);
            // Depth: faster streams look closer (brighter), with some random variation.
            let near = if sv > 1.0 { (speed - 1.0) / (sv - 1.0) } else { 0.5 };
            let depth = 0.55 * near + 0.45 * self.rng.unit();
            let len = if self.p.monotonous {
                self.p.back_trace.max(2)
            } else {
                tmin + self.rng.below((tmax - tmin + 1) as usize) as i32
            };
            let head = -1 - self.rng.below(8) as i32;
            self.slots[slot as usize] = Slot { head, len };
            self.streams.push(Stream {
                col,
                slot,
                head,
                len,
                speed,
                shade: (45.0 + 210.0 * depth) as u8,
                acc: 0.0,
                special,
                owns_col: true,
            });
        }
    }

    /// Moves one stream down by a row; returns false when it has left the screen.
    fn step(&mut self, si: usize) -> bool {
        let rows = self.rows as i32;
        let (col, len, shade, special, sid) = {
            let s = &self.streams[si];
            (s.col, s.len, s.shade, s.special, s.slot)
        };
        let head = self.streams[si].head + 1;
        self.streams[si].head = head;
        self.slots[sid as usize].head = head;

        if head - 1 >= 0 && head - 1 < rows {
            let cell = &mut self.cells[(head - 1) as usize * self.cols + col];
            if cell.sid == sid {
                cell.flags &= !F_HEAD;
            }
        }
        if head >= 0 && head < rows {
            let mut flags = F_ON | F_HEAD | if special.is_some() { F_SPECIAL_STREAM } else { 0 };
            let mut glyph = self.rng.below(self.p.charset_len) as u16;
            if let Some((idx, start)) = special {
                let s = &self.p.special_strings[idx];
                let off = head - start;
                if off >= 0 && (off as usize) < s.len() {
                    glyph = s[off as usize];
                    flags |= F_SPECIAL_GLYPH;
                }
            }
            self.cells[head as usize * self.cols + col] = Cell { glyph, flags, shade, sid };
        }
        if head >= rows && self.streams[si].owns_col {
            // The head has left the screen: the column may start a new stream.
            self.streams[si].owns_col = false;
            self.occupied[col] = false;
        }
        // The end of the trail is erased as the head moves on.
        self.clear_own(col, head - len, sid);
        if self.p.randomized {
            let hi = head - self.p.leading;
            let lo = hi - self.p.space_pad;
            let r = lo + self.rng.below((hi - lo + 1).max(1) as usize) as i32;
            self.clear_own(col, r, sid);
        }
        head - len < rows
    }

    /// Random character changes inside the streams: this is what makes the rain shimmer.
    fn flicker(&mut self, dt_ms: f32) {
        for c in self.cells.iter_mut() {
            c.flags &= !F_FLASH;
        }
        let s = self.p.flicker;
        let hs = self.p.head_flicker;
        if s <= 0.0 && hs <= 0.0 {
            return;
        }
        let k = (dt_ms / 33.0).clamp(0.3, 3.0);
        // 8 attempts per frame: at strength 0.5 about 4 characters of each trail change.
        let p_mut = (s * k).min(1.0);
        for si in 0..self.streams.len() {
            let (col, head, len, sid) = {
                let st = &self.streams[si];
                (st.col, st.head, st.len, st.slot)
            };
            // Head shimmer.
            if self.rng.unit() < hs {
                self.mutate(col, head, sid, false);
            }
            for n in 0..8 {
                if self.rng.unit() > p_mut {
                    continue;
                }
                let row = head - 1 - self.rng.below(len.max(1) as usize) as i32;
                let flash = n < 2 && self.rng.unit() < s * 0.5;
                self.mutate(col, row, sid, flash);
            }
        }
    }

    fn mutate(&mut self, col: usize, row: i32, sid: u16, flash: bool) {
        if row < 0 || row >= self.rows as i32 {
            return;
        }
        let g = self.rng.below(self.p.charset_len) as u16;
        let cell = &mut self.cells[row as usize * self.cols + col];
        if cell.flags & F_ON != 0 && cell.sid == sid && cell.flags & F_SPECIAL_GLYPH == 0 {
            cell.glyph = g;
            if flash {
                cell.flags |= F_FLASH;
            }
        }
    }

    /// Advances the simulation by `dt_ms`.
    pub fn advance(&mut self, dt_ms: f32) {
        self.spawn(dt_ms);
        self.flicker(dt_ms);
        let mut i = 0;
        while i < self.streams.len() {
            let s = &mut self.streams[i];
            s.acc += dt_ms * s.speed;
            let n = ((s.acc / self.p.refresh_ms) as u32).min(64);
            s.acc = if n == 64 { 0.0 } else { s.acc - n as f32 * self.p.refresh_ms };
            let mut alive = true;
            for _ in 0..n {
                if !self.step(i) {
                    alive = false;
                    break;
                }
            }
            if alive {
                i += 1;
            } else {
                let st = self.streams.swap_remove(i);
                if st.owns_col {
                    self.occupied[st.col] = false;
                }
                self.free_slots.push(st.slot);
            }
        }
    }
}
