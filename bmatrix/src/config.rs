//! Parser for the `default.cfg` settings format (INI-style, all keys optional).

use std::collections::HashMap;

pub const DEFAULT_CFG: &str = include_str!("../assets/default.cfg");

#[derive(Clone, Copy, Debug)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Debug)]
pub struct FontSpec {
    pub height: i32,
    pub weight: i32,
    pub italic: bool,
    pub name: String,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Blend {
    Or,
    And,
    Xor,
    Copy,
}

#[derive(Clone, Debug)]
pub struct Config {
    pub max_stream: usize,
    pub speed_variance: f32,
    pub monotonous_cleanup: bool,
    pub back_trace: i32,
    pub randomized_cleanup: bool,
    pub leading: i32,
    pub space_pad: i32,
    pub refresh_ms: u32,
    /// Win32 priority class name, e.g. `IDLE_PRIORITY_CLASS`.
    pub priority: String,
    pub special_probability: f32,
    pub text: FontSpec,
    pub special_font: FontSpec,
    pub charset: Vec<char>,
    pub special_strings: Vec<Vec<char>>,
    pub fg: Rgba,
    pub fade: Rgba,
    pub bg: Rgba,
    pub special_fg: Rgba,
    pub special_fade: Rgba,
    pub bg_bitmap: bool,
    pub blend: Blend,
    /// Optional BAVtrix extension `[Colors] OverlayOpacity` (0-255): how strongly the
    /// desktop overlay hides the desktop. Not part of the classic key set.
    pub overlay_opacity: u8,
    /// Optional BAVtrix extension `[General] SpawnRate` (0-1): rain density.
    pub spawn_rate: f32,
    /// Optional BAVtrix extension `[General] Flicker` (0-1): shimmer strength.
    pub flicker: f32,
    /// Optional BAVtrix extension `[General] HeadFlicker` (0-1): how often the head symbol changes.
    pub head_flicker: f32,
    /// Optional BAVtrix extension `[General] HeadBrightness` (0.5-2): head and flash brightness.
    pub head_brightness: f32,
    /// Optional BAVtrix extensions `[General] TrailMin` / `TrailMax` (rows, 0 = automatic).
    pub trail_min: i32,
    pub trail_max: i32,
}

type Map = HashMap<String, String>;

fn parse_ini(src: &str) -> Map {
    let mut map = Map::new();
    let mut section = String::new();
    for line in src.lines() {
        let line = line.trim().trim_start_matches('\u{feff}');
        if line.is_empty() || line.starts_with(';') {
            continue;
        }
        if let Some(rest) = line.strip_prefix('[') {
            section = rest.trim_end_matches(']').to_string();
        } else if let Some((k, v)) = line.split_once('=') {
            map.insert(format!("{}.{}", section, k.trim()), v.trim().to_string());
        }
    }
    map
}

fn num<T: std::str::FromStr>(m: &Map, key: &str, default: T) -> T {
    m.get(key).and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn flag(m: &Map, key: &str, default: bool) -> bool {
    m.get(key)
        .and_then(|v| v.parse::<i32>().ok())
        .map(|v| v != 0)
        .unwrap_or(default)
}

fn color(m: &Map, key: &str, default: Rgba) -> Rgba {
    let Some(v) = m.get(key) else { return default };
    let n: Vec<u8> = v
        .split(|c: char| !c.is_ascii_digit())
        .filter(|s| !s.is_empty())
        .filter_map(|s| s.parse::<u16>().ok())
        .map(|x| x.min(255) as u8)
        .collect();
    if n.len() >= 4 {
        Rgba { r: n[0], g: n[1], b: n[2], a: n[3] }
    } else {
        default
    }
}

fn font(m: &Map, sec: &str, def_name: &str, def_h: i32) -> FontSpec {
    FontSpec {
        height: num(m, &format!("{sec}.FontHeight"), def_h),
        weight: num(m, &format!("{sec}.FontWeight"), 400),
        italic: flag(m, &format!("{sec}.FontItalic"), false),
        name: m
            .get(&format!("{sec}.FontName"))
            .cloned()
            .unwrap_or_else(|| def_name.to_string()),
    }
}

/// Parses a character list with these escape rules:
/// separators are whitespace and ',', `\\` and `\,` are literals, `\0xHHHH` is a Unicode code point.
pub fn parse_charset(s: &str) -> Vec<char> {
    let mut out = Vec::new();
    let chars: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\\' && i + 1 < chars.len() {
            let n = chars[i + 1];
            if n == '\\' || n == ',' {
                out.push(n);
                i += 2;
                continue;
            }
            if n == '0' && i + 2 < chars.len() && (chars[i + 2] == 'x' || chars[i + 2] == 'X') {
                let mut j = i + 3;
                let mut v = 0u32;
                while j < chars.len() && chars[j].is_ascii_hexdigit() {
                    v = v * 16 + chars[j].to_digit(16).unwrap();
                    j += 1;
                }
                if let Some(ch) = char::from_u32(v) {
                    out.push(ch);
                }
                i = j;
                continue;
            }
            i += 1;
            continue;
        }
        if c != ',' && !c.is_whitespace() {
            out.push(c);
        }
        i += 1;
    }
    out
}

impl Config {
    pub fn parse(src: &str) -> Config {
        let m = parse_ini(src);
        let white = Rgba { r: 255, g: 255, b: 255, a: 255 };
        let mut charset = parse_charset(m.get("Text.CharSet").map(String::as_str).unwrap_or(""));
        if charset.is_empty() {
            charset = "1234567890ABCDEFGHIJKLMNOPQRSUTVWXYZabcd".chars().collect();
        }
        let special_strings = m
            .get("SpecialText.Strings")
            .map(|s| {
                s.split('|')
                    .map(|p| p.chars().collect::<Vec<_>>())
                    .filter(|p| !p.is_empty())
                    .collect()
            })
            .unwrap_or_default();
        let blend_name = m.get("Colors.BlendMode").map(|s| s.to_uppercase()).unwrap_or_default();
        let blend = if blend_name.contains("XOR") {
            Blend::Xor
        } else if blend_name.contains("AND") {
            Blend::And
        } else if blend_name.contains("COPY") {
            Blend::Copy
        } else {
            Blend::Or
        };
        let mut p: f32 = num(&m, "General.SpecialStringStreamProbability", 0.1);
        if p > 1.0 {
            p /= 100.0;
        }
        Config {
            max_stream: num(&m, "General.MaxStream", 1000usize).max(1),
            speed_variance: num(&m, "General.SpeedVariance", 5.0f32).max(1.0),
            monotonous_cleanup: flag(&m, "General.MonotonousCleanupEnabled", false),
            back_trace: num(&m, "General.BackTrace", 40),
            randomized_cleanup: flag(&m, "General.RandomizedCleanupEnabled", false),
            leading: num(&m, "General.Leading", 10),
            space_pad: num(&m, "General.SpacePad", 30),
            refresh_ms: num(&m, "General.RefreshTime", 50u32).max(1),
            priority: m
                .get("General.PriorityClass")
                .cloned()
                .unwrap_or_else(|| "IDLE_PRIORITY_CLASS".to_string()),
            special_probability: p.clamp(0.0, 1.0),
            text: font(&m, "Text", "Matrix Code Font", -7),
            special_font: font(&m, "SpecialText", "Terminal", -8),
            charset,
            special_strings,
            fg: color(&m, "Colors.FGColor", white),
            fade: color(&m, "Colors.FadeColor", Rgba { r: 0, g: 128, b: 0, a: 255 }),
            bg: color(&m, "Colors.BGColor", Rgba { r: 0, g: 0, b: 0, a: 0 }),
            special_fg: color(&m, "Colors.SpecialStringFGColor", white),
            special_fade: color(&m, "Colors.SpecialStringFadeColor", white),
            bg_bitmap: m
                .get("Colors.BGMode")
                .map(|v| v.to_lowercase().contains("bitmap"))
                .unwrap_or(true),
            blend,
            overlay_opacity: num(&m, "Colors.OverlayOpacity", 255u8),
            spawn_rate: num(&m, "General.SpawnRate", 0.25f32).clamp(0.001, 1.0),
            flicker: num(&m, "General.Flicker", 0.25f32).clamp(0.0, 1.0),
            head_flicker: num(&m, "General.HeadFlicker", 1.0f32).clamp(0.0, 1.0),
            head_brightness: num(&m, "General.HeadBrightness", 1.3f32).clamp(0.5, 2.0),
            trail_min: num(&m, "General.TrailMin", 8i32).max(2),
            trail_max: num(&m, "General.TrailMax", 0i32).max(0),
        }
    }
}

/// Location of `default.cfg` (next to the executable).
pub fn config_path() -> Option<std::path::PathBuf> {
    std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.join("default.cfg")))
}

/// Raw text of the config file, or the built-in defaults.
pub fn load_text() -> String {
    config_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .unwrap_or_else(|| DEFAULT_CFG.to_string())
}

pub fn load() -> Config {
    Config::parse(&load_text())
}

/// Line-preserving INI editor: updates keys in place and keeps everything else untouched.
pub struct IniDoc {
    lines: Vec<String>,
}

impl IniDoc {
    pub fn new(src: &str) -> IniDoc {
        IniDoc { lines: src.trim_start_matches('\u{feff}').lines().map(str::to_string).collect() }
    }

    pub fn set(&mut self, section: &str, key: &str, value: &str) {
        let header = format!("[{section}]");
        let Some(start) = self.lines.iter().position(|l| l.trim() == header) else {
            self.lines.push(header);
            self.lines.push(format!("{key}={value}"));
            return;
        };
        let mut end = self.lines.len();
        for i in start + 1..self.lines.len() {
            let t = self.lines[i].trim();
            if t.starts_with('[') {
                end = i;
                break;
            }
            if t.split_once('=').map(|(k, _)| k.trim() == key).unwrap_or(false) {
                self.lines[i] = format!("{key}={value}");
                return;
            }
        }
        let mut at = end;
        while at > start + 1 && self.lines[at - 1].trim().is_empty() {
            at -= 1;
        }
        self.lines.insert(at, format!("{key}={value}"));
    }

    pub fn text(&self) -> String {
        self.lines.join("\r\n") + "\r\n"
    }
}

fn rgba_str(c: Rgba) -> String {
    format!("{{{},{},{},{}}}", c.r, c.g, c.b, c.a)
}

fn num_str(v: f32) -> String {
    if v.fract() == 0.0 { format!("{}", v as i64) } else { format!("{v}") }
}

/// Character list in the same syntax (`,`-separated, non-ASCII as `\0xHHHH`).
pub fn charset_text(chars: &[char]) -> String {
    chars
        .iter()
        .map(|&c| match c {
            '\\' => r"\\".to_string(),
            ',' => r"\,".to_string(),
            c if c.is_ascii() => c.to_string(),
            c => format!(r"\0x{:04X}", c as u32),
        })
        .collect::<Vec<_>>()
        .join(", ")
}

impl Config {
    /// Writes every setting into `existing` and returns the new file text.
    pub fn serialize(&self, existing: &str) -> String {
        let mut d = IniDoc::new(existing);
        let b = |v: bool| if v { "1" } else { "0" };
        d.set("General", "MaxStream", &self.max_stream.to_string());
        d.set("General", "SpeedVariance", &num_str(self.speed_variance));
        d.set("General", "MonotonousCleanupEnabled", b(self.monotonous_cleanup));
        d.set("General", "BackTrace", &self.back_trace.to_string());
        d.set("General", "RandomizedCleanupEnabled", b(self.randomized_cleanup));
        d.set("General", "Leading", &self.leading.to_string());
        d.set("General", "SpacePad", &self.space_pad.to_string());
        d.set("General", "RefreshTime", &self.refresh_ms.to_string());
        d.set("General", "PriorityClass", &self.priority);
        d.set("General", "SpecialStringStreamProbability", &format!("{}", self.special_probability));
        d.set("General", "SpawnRate", &format!("{}", self.spawn_rate));
        d.set("General", "Flicker", &format!("{}", self.flicker));
        d.set("General", "HeadFlicker", &format!("{}", self.head_flicker));
        d.set("General", "HeadBrightness", &format!("{}", self.head_brightness));
        d.set("General", "TrailMin", &self.trail_min.to_string());
        d.set("General", "TrailMax", &self.trail_max.to_string());
        for (sec, f) in [("Text", &self.text), ("SpecialText", &self.special_font)] {
            d.set(sec, "FontHeight", &f.height.to_string());
            d.set(sec, "FontWeight", &f.weight.to_string());
            d.set(sec, "FontItalic", b(f.italic));
            d.set(sec, "FontName", &f.name);
        }
        d.set("Text", "CharSet", &charset_text(&self.charset));
        d.set("Colors", "FGColor", &rgba_str(self.fg));
        d.set("Colors", "FadeColor", &rgba_str(self.fade));
        d.set("Colors", "BGColor", &rgba_str(self.bg));
        d.set("Colors", "SpecialStringFGColor", &rgba_str(self.special_fg));
        d.set("Colors", "SpecialStringFadeColor", &rgba_str(self.special_fade));
        d.set("Colors", "BGMode", if self.bg_bitmap { "bgmodeBitmap" } else { "bgmodeColor" });
        let blend = match self.blend {
            Blend::Or => "blendmodeOR",
            Blend::And => "blendmodeAND",
            Blend::Xor => "blendmodeXOR",
            Blend::Copy => "blendmodeCOPY",
        };
        d.set("Colors", "BlendMode", blend);
        let strings: Vec<String> = self.special_strings.iter().map(|s| s.iter().collect()).collect();
        d.set("SpecialText", "Strings", &strings.join("|"));
        d.text()
    }
}
