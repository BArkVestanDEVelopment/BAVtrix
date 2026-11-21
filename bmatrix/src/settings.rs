//! Settings dialog with the tabs General, Cleanup, Colors, Background and Text:
//! tabs General, Cleanup, Colors, Background and Text. Built from plain Win32 controls.

use crate::atlas::wide;
use crate::config::{self, Blend, Config, FontSpec, Rgba};
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Controls::Dialogs::*;
use windows_sys::Win32::UI::Controls::*;
use windows_sys::Win32::UI::HiDpi::GetDpiForSystem;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const ID_OK: usize = 1;
const ID_CANCEL: usize = 2;
const ID_DEFAULTS: usize = 3;
const ID_EDIT: usize = 2000;
const ID_COLOR: usize = 3100;
const ID_FONT: usize = 3200;

const PAGES: usize = 5;
const TAB_NAMES: [&str; PAGES] = ["General", "Cleanup", "Colors", "Background", "Text"];

/// (label, min, max, page)
const ROWS: [(&str, i32, i32, usize); 13] = [
    ("Макс. потоков (Max Stream)", 1, 2000, 0),
    ("Разброс скоростей (Speed Variance)", 1, 20, 0),
    ("Спецстрока, % (Special String)", 0, 100, 0),
    ("Время обновления, мс (Refresh Time)", 1, 500, 0),
    ("Плотность потоков, % (Spawn Rate)", 1, 100, 0),
    ("Back Trace", 1, 200, 1),
    ("Leading", 0, 100, 1),
    ("Space Pad", 0, 200, 1),
    ("Мерцание, % (Flicker)", 0, 100, 0),
    ("Мин. длина шлейфа, строк (Trail Min)", 2, 200, 1),
    ("Макс. шлейф, 0 = авто (Trail Max)", 0, 300, 1),
    ("Мерцание головы, % (Head Flicker)", 0, 100, 0),
    ("Яркость головы, % (Head Brightness)", 50, 200, 0),
];

const COLOR_NAMES: [&str; 5] = [
    "Шлейф (Fade)",
    "Голова потока (Foreground)",
    "Фон (Background)",
    "Голова спецстроки",
    "Шлейф спецстроки",
];

const PRIORITIES: [(&str, &str); 5] = [
    ("IDLE_PRIORITY_CLASS", "Низкий (Idle)"),
    ("BELOW_NORMAL_PRIORITY_CLASS", "Ниже обычного"),
    ("NORMAL_PRIORITY_CLASS", "Обычный"),
    ("ABOVE_NORMAL_PRIORITY_CLASS", "Выше обычного"),
    ("HIGH_PRIORITY_CLASS", "Высокий"),
];

const BLENDS: [(&str, Blend); 4] = [
    ("OR", Blend::Or),
    ("AND", Blend::And),
    ("XOR", Blend::Xor),
    ("Copy", Blend::Copy),
];

struct Ui {
    hwnd: HWND,
    tab: HWND,
    ui_font: HFONT,
    scale: f32,
    standalone: bool,
    cfg: Config,
    pages: Vec<Vec<HWND>>,
    tracks: Vec<HWND>,
    edits: Vec<HWND>,
    mono: HWND,
    rand: HWND,
    prio: HWND,
    swatches: Vec<HWND>,
    brushes: Vec<HBRUSH>,
    mode: Vec<HWND>,
    blend: Vec<HWND>,
    font_labels: Vec<HWND>,
    charset: HWND,
    strings: HWND,
    updating: bool,
}

static mut UI: *mut Ui = null_mut();

fn colorref(c: Rgba) -> u32 {
    (c.b as u32) << 16 | (c.g as u32) << 8 | c.r as u32
}

unsafe fn text_of(h: HWND) -> String {
    let n = GetWindowTextLengthW(h);
    let mut buf = vec![0u16; n as usize + 1];
    GetWindowTextW(h, buf.as_mut_ptr(), n + 1);
    String::from_utf16_lossy(&buf[..n as usize])
}

unsafe fn set_text(h: HWND, s: &str) {
    SetWindowTextW(h, wide(s).as_ptr());
}

fn colors_of(cfg: &Config) -> [Rgba; 5] {
    [cfg.fade, cfg.fg, cfg.bg, cfg.special_fg, cfg.special_fade]
}

fn set_color(cfg: &mut Config, i: usize, c: Rgba) {
    match i {
        0 => cfg.fade = c,
        1 => cfg.fg = c,
        2 => cfg.bg = c,
        3 => cfg.special_fg = c,
        _ => cfg.special_fade = c,
    }
}

fn row_values(cfg: &Config) -> [i32; 13] {
    [
        cfg.max_stream as i32,
        cfg.speed_variance.round() as i32,
        (cfg.special_probability * 100.0).round() as i32,
        cfg.refresh_ms as i32,
        (cfg.spawn_rate * 100.0).round() as i32,
        cfg.back_trace,
        cfg.leading,
        cfg.space_pad,
        (cfg.flicker * 100.0).round() as i32,
        cfg.trail_min,
        cfg.trail_max,
        (cfg.head_flicker * 100.0).round() as i32,
        (cfg.head_brightness * 100.0).round() as i32,
    ]
}

fn font_label(f: &FontSpec) -> String {
    format!("{}, {} px{}", f.name, f.height.abs(), if f.italic { ", курсив" } else { "" })
}

unsafe fn ctl(ui: &Ui, class: &str, text: &str, style: u32, ex: u32, r: (i32, i32, i32, i32), id: usize) -> HWND {
    let s = ui.scale;
    let h = CreateWindowExW(
        ex,
        wide(class).as_ptr(),
        wide(text).as_ptr(),
        WS_CHILD | WS_VISIBLE | style,
        (r.0 as f32 * s) as i32,
        (r.1 as f32 * s) as i32,
        (r.2 as f32 * s) as i32,
        (r.3 as f32 * s) as i32,
        ui.hwnd,
        id as *mut core::ffi::c_void,
        GetModuleHandleW(null()),
        null(),
    );
    SendMessageW(h, WM_SETFONT, ui.ui_font as WPARAM, 1);
    h
}

const WS_TAB: u32 = 0x0001_0000; // WS_TABSTOP
const WS_GRP: u32 = 0x0002_0000; // WS_GROUP

unsafe fn build(ui: &mut Ui) {
    ui.updating = true;
    build_controls(ui);
    ui.updating = false;
}

unsafe fn build_controls(ui: &mut Ui) {
    let vals = row_values(&ui.cfg);
    ui.pages = vec![Vec::new(); PAGES];

    // Numeric rows (label + slider + edit).
    let mut ys = [48i32; PAGES];
    for (i, (label, min, max, page)) in ROWS.iter().enumerate() {
        let y = ys[*page];
        ys[*page] += 32;
        let lbl = ctl(ui, "STATIC", label, 0, 0, (20, y + 4, 240, 20), 0);
        let track = ctl(ui, "msctls_trackbar32", "", WS_TAB | 0x0010 /* TBS_NOTICKS */, 0, (264, y, 190, 28), 4000 + i);
        SendMessageW(track, 0x0406, 1, ((*max as isize) << 16) | (*min as isize & 0xFFFF)); // TBM_SETRANGE
        SendMessageW(track, 0x0405, 1, vals[i] as isize); // TBM_SETPOS
        let edit = ctl(ui, "EDIT", &vals[i].to_string(), WS_TAB | 0x2000 | 0x0080, WS_EX_CLIENTEDGE, (462, y + 2, 64, 22), ID_EDIT + i);
        ui.pages[*page].extend([lbl, track, edit]);
        ui.tracks.push(track);
        ui.edits.push(edit);
    }

    // General: process priority.
    let y = ys[0] + 6;
    let lbl = ctl(ui, "STATIC", "Приоритет процесса (Priority)", 0, 0, (20, y + 4, 215, 20), 0);
    ui.prio = ctl(ui, "COMBOBOX", "", WS_TAB | 0x0003 /* CBS_DROPDOWNLIST */ | WS_VSCROLL, 0, (240, y, 215, 200), 0);
    for (_, name) in PRIORITIES {
        SendMessageW(ui.prio, 0x0143, 0, wide(name).as_ptr() as isize); // CB_ADDSTRING
    }
    let cur = PRIORITIES
        .iter()
        .position(|(k, _)| *k == ui.cfg.priority)
        .unwrap_or(0);
    SendMessageW(ui.prio, 0x014E, cur, 0); // CB_SETCURSEL
    ui.pages[0].extend([lbl, ui.prio]);

    // Cleanup: enable checkboxes.
    ui.mono = ctl(ui, "BUTTON", "Монотонная зачистка (Monotonous Cleanup)", WS_TAB | 0x0003, 0, (20, ys[1] + 4, 400, 22), 0);
    ui.rand = ctl(ui, "BUTTON", "Случайная зачистка (Randomized Cleanup)", WS_TAB | 0x0003, 0, (20, ys[1] + 30, 400, 22), 0);
    SendMessageW(ui.mono, 0x00F1, ui.cfg.monotonous_cleanup as usize, 0); // BM_SETCHECK
    SendMessageW(ui.rand, 0x00F1, ui.cfg.randomized_cleanup as usize, 0);
    let note = ctl(
        ui,
        "STATIC",
        "Длина шлейфа: если монотонная зачистка выключена, у каждого потока своя длина от Trail Min до Trail Max; при включённой — везде Back Trace.",
        0,
        0,
        (20, ys[1] + 58, 510, 40),
        0,
    );
    ui.pages[1].extend([ui.mono, ui.rand, note]);

    // Colors.
    let colors = colors_of(&ui.cfg);
    for (i, name) in COLOR_NAMES.iter().enumerate() {
        let y = 52 + i as i32 * 44;
        let lbl = ctl(ui, "STATIC", name, 0, 0, (20, y + 6, 230, 20), 0);
        let sw = ctl(ui, "STATIC", "", 0, WS_EX_CLIENTEDGE, (260, y, 80, 28), 3000 + i);
        let btn = ctl(ui, "BUTTON", "Выбрать...", WS_TAB, 0, (352, y, 110, 28), ID_COLOR + i);
        ui.brushes.push(CreateSolidBrush(colorref(colors[i])));
        ui.swatches.push(sw);
        ui.pages[2].extend([lbl, sw, btn]);
    }

    // Background.
    let g1 = ctl(ui, "BUTTON", "Режим (Mode)", 0x0007 /* BS_GROUPBOX */, 0, (16, 48, 510, 70), 0);
    let m0 = ctl(ui, "BUTTON", "Картинка рабочего стола (Bitmap)", WS_TAB | WS_GRP | 0x0009, 0, (32, 70, 450, 20), 0);
    let m1 = ctl(ui, "BUTTON", "Сплошной цвет (Color)", 0x0009, 0, (32, 92, 450, 20), 0);
    SendMessageW(if ui.cfg.bg_bitmap { m0 } else { m1 }, 0x00F1, 1, 0);
    ui.mode = vec![m0, m1];
    let g2 = ctl(ui, "BUTTON", "Смешивание (Blending)", 0x0007, 0, (16, 130, 510, 70), 0);
    ui.pages[3].extend([g1, m0, m1, g2]);
    for (i, (name, kind)) in BLENDS.iter().enumerate() {
        let style = WS_TAB * (i == 0) as u32 | WS_GRP * (i == 0) as u32 | 0x0009;
        let rb = ctl(ui, "BUTTON", name, style, 0, (32 + i as i32 * 120, 160, 110, 20), 0);
        if *kind == ui.cfg.blend {
            SendMessageW(rb, 0x00F1, 1, 0);
        }
        ui.blend.push(rb);
        ui.pages[3].push(rb);
    }
    let note = ctl(
        ui,
        "STATIC",
        "Картинка рабочего стола смешивается с цветом символов выбранной операцией — так обои проступают через дождь другим цветом.",
        0,
        0,
        (16, 216, 510, 40),
        0,
    );
    ui.pages[3].push(note);

    // Text.
    let fonts = [ui.cfg.text.clone(), ui.cfg.special_font.clone()];
    for (i, f) in fonts.iter().enumerate() {
        let y = 48 + i as i32 * 36;
        let btn = ctl(ui, "BUTTON", if i == 0 { "Шрифт..." } else { "Шрифт спецстрок..." }, WS_TAB, 0, (20, y, 150, 26), ID_FONT + i);
        let lbl = ctl(ui, "STATIC", &font_label(f), 0, 0, (182, y + 4, 340, 20), 0);
        ui.font_labels.push(lbl);
        ui.pages[4].extend([btn, lbl]);
    }
    let l1 = ctl(ui, "STATIC", "Набор символов (Character Set)", 0, 0, (20, 124, 400, 18), 0);
    ui.charset = ctl(
        ui,
        "EDIT",
        &config::charset_text(&ui.cfg.charset),
        WS_TAB | 0x0004 | 0x0040 | WS_VSCROLL, // ES_MULTILINE | ES_AUTOVSCROLL
        WS_EX_CLIENTEDGE,
        (20, 144, 506, 62),
        0,
    );
    let l2 = ctl(ui, "STATIC", "Спецстроки, по одной на строку (Special Strings)", 0, 0, (20, 214, 450, 18), 0);
    let lines: Vec<String> = ui.cfg.special_strings.iter().map(|s| s.iter().collect()).collect();
    ui.strings = ctl(
        ui,
        "EDIT",
        &lines.join("\r\n"),
        WS_TAB | 0x0004 | 0x0040 | WS_VSCROLL,
        WS_EX_CLIENTEDGE,
        (20, 234, 506, 62),
        0,
    );
    ui.pages[4].extend([l1, ui.charset, l2, ui.strings]);

    // Buttons.
    ctl(ui, "BUTTON", "OK", WS_TAB | 0x0001 /* BS_DEFPUSHBUTTON */, 0, (284, 372, 80, 28), ID_OK);
    ctl(ui, "BUTTON", "Отмена", WS_TAB, 0, (372, 372, 80, 28), ID_CANCEL);
    ctl(ui, "BUTTON", "По умолчанию", WS_TAB, 0, (16, 372, 120, 28), ID_DEFAULTS);

    show_page(ui, 0);
}

unsafe fn show_page(ui: &Ui, page: usize) {
    for (i, controls) in ui.pages.iter().enumerate() {
        for &h in controls {
            ShowWindow(h, if i == page { SW_SHOW } else { SW_HIDE });
        }
    }
}

/// Copies a config's values into the existing controls (used by "По умолчанию").
unsafe fn load_into_controls(ui: &mut Ui, cfg: Config) {
    ui.updating = true;
    let vals = row_values(&cfg);
    for i in 0..ROWS.len() {
        SendMessageW(ui.tracks[i], 0x0405, 1, vals[i] as isize);
        set_text(ui.edits[i], &vals[i].to_string());
    }
    SendMessageW(ui.mono, 0x00F1, cfg.monotonous_cleanup as usize, 0);
    SendMessageW(ui.rand, 0x00F1, cfg.randomized_cleanup as usize, 0);
    SendMessageW(ui.prio, 0x014E, PRIORITIES.iter().position(|(k, _)| *k == cfg.priority).unwrap_or(0), 0);
    for (i, c) in colors_of(&cfg).iter().enumerate() {
        DeleteObject(ui.brushes[i]);
        ui.brushes[i] = CreateSolidBrush(colorref(*c));
        InvalidateRect(ui.swatches[i], null(), 1);
    }
    SendMessageW(ui.mode[0], 0x00F1, cfg.bg_bitmap as usize, 0);
    SendMessageW(ui.mode[1], 0x00F1, !cfg.bg_bitmap as usize, 0);
    for (i, (_, kind)) in BLENDS.iter().enumerate() {
        SendMessageW(ui.blend[i], 0x00F1, (*kind == cfg.blend) as usize, 0);
    }
    set_text(ui.font_labels[0], &font_label(&cfg.text));
    set_text(ui.font_labels[1], &font_label(&cfg.special_font));
    set_text(ui.charset, &config::charset_text(&cfg.charset));
    let lines: Vec<String> = cfg.special_strings.iter().map(|s| s.iter().collect()).collect();
    set_text(ui.strings, &lines.join("\r\n"));
    ui.cfg = cfg;
    ui.updating = false;
}

unsafe fn pick_color(ui: &mut Ui, i: usize) {
    let current = colors_of(&ui.cfg)[i];
    static mut CUSTOM: [u32; 16] = [0; 16];
    let mut cc: CHOOSECOLORW = std::mem::zeroed();
    cc.lStructSize = std::mem::size_of::<CHOOSECOLORW>() as u32;
    cc.hwndOwner = ui.hwnd;
    cc.rgbResult = colorref(current);
    cc.lpCustColors = std::ptr::addr_of_mut!(CUSTOM) as *mut u32;
    cc.Flags = 0x1 | 0x2; // CC_RGBINIT | CC_FULLOPEN
    if ChooseColorW(&mut cc) != 0 {
        let c = cc.rgbResult;
        let new = Rgba { r: (c & 0xFF) as u8, g: ((c >> 8) & 0xFF) as u8, b: ((c >> 16) & 0xFF) as u8, a: current.a };
        set_color(&mut ui.cfg, i, new);
        DeleteObject(ui.brushes[i]);
        ui.brushes[i] = CreateSolidBrush(colorref(new));
        InvalidateRect(ui.swatches[i], null(), 1);
    }
}

unsafe fn pick_font(ui: &mut Ui, which: usize) {
    let spec = if which == 0 { ui.cfg.text.clone() } else { ui.cfg.special_font.clone() };
    let dpi = GetDpiForSystem() as i32;
    let mut lf: LOGFONTW = std::mem::zeroed();
    lf.lfHeight = -(spec.height.abs() * dpi / 96);
    lf.lfWeight = spec.weight;
    lf.lfItalic = spec.italic as u8;
    for (i, c) in spec.name.encode_utf16().take(31).enumerate() {
        lf.lfFaceName[i] = c;
    }
    let mut cf: CHOOSEFONTW = std::mem::zeroed();
    cf.lStructSize = std::mem::size_of::<CHOOSEFONTW>() as u32;
    cf.hwndOwner = ui.hwnd;
    cf.lpLogFont = &mut lf;
    cf.Flags = 0x1 | 0x40; // CF_SCREENFONTS | CF_INITTOLOGFONTSTRUCT
    if ChooseFontW(&mut cf) != 0 {
        let end = lf.lfFaceName.iter().position(|&c| c == 0).unwrap_or(32);
        let new = FontSpec {
            height: -((lf.lfHeight.abs() * 96 / dpi).max(1)),
            weight: lf.lfWeight,
            italic: lf.lfItalic != 0,
            name: String::from_utf16_lossy(&lf.lfFaceName[..end]),
        };
        set_text(ui.font_labels[which], &font_label(&new));
        if which == 0 {
            ui.cfg.text = new;
        } else {
            ui.cfg.special_font = new;
        }
    }
}

/// Reads all controls into a Config.
unsafe fn collect(ui: &Ui) -> Config {
    let mut cfg = ui.cfg.clone();
    let mut v = [0i32; 13];
    for (i, (_, min, max, _)) in ROWS.iter().enumerate() {
        let parsed = text_of(ui.edits[i]).trim().parse::<i32>().unwrap_or(*min);
        v[i] = parsed.clamp(*min, *max);
    }
    cfg.max_stream = v[0] as usize;
    cfg.speed_variance = v[1] as f32;
    cfg.special_probability = v[2] as f32 / 100.0;
    cfg.refresh_ms = v[3] as u32;
    cfg.spawn_rate = v[4] as f32 / 100.0;
    cfg.back_trace = v[5];
    cfg.leading = v[6];
    cfg.space_pad = v[7];
    cfg.flicker = v[8] as f32 / 100.0;
    cfg.trail_min = v[9];
    cfg.trail_max = v[10];
    cfg.head_flicker = v[11] as f32 / 100.0;
    cfg.head_brightness = v[12] as f32 / 100.0;
    cfg.monotonous_cleanup = SendMessageW(ui.mono, 0x00F0, 0, 0) == 1; // BM_GETCHECK
    cfg.randomized_cleanup = SendMessageW(ui.rand, 0x00F0, 0, 0) == 1;
    let p = SendMessageW(ui.prio, 0x0147, 0, 0) as usize; // CB_GETCURSEL
    cfg.priority = PRIORITIES.get(p).map(|(k, _)| k.to_string()).unwrap_or_else(|| PRIORITIES[0].0.to_string());
    cfg.bg_bitmap = SendMessageW(ui.mode[0], 0x00F0, 0, 0) == 1;
    for (i, (_, kind)) in BLENDS.iter().enumerate() {
        if SendMessageW(ui.blend[i], 0x00F0, 0, 0) == 1 {
            cfg.blend = *kind;
        }
    }
    let chars = config::parse_charset(&text_of(ui.charset));
    if !chars.is_empty() {
        cfg.charset = chars;
    }
    cfg.special_strings = text_of(ui.strings)
        .lines()
        .map(|l| l.trim_end_matches('\r').chars().collect::<Vec<char>>())
        .filter(|l| !l.is_empty())
        .collect();
    cfg
}

unsafe fn save_and_close(ui: &mut Ui) {
    let cfg = collect(ui);
    let text = cfg.serialize(&config::load_text());
    if let Some(path) = config::config_path() {
        if std::fs::write(&path, text).is_err() {
            MessageBoxW(
                ui.hwnd,
                wide("Не удалось записать default.cfg. Закройте программы, использующие файл, и повторите.").as_ptr(),
                wide("BAVtrix").as_ptr(),
                0x10,
            );
            return;
        }
    }
    let standalone = ui.standalone;
    DestroyWindow(ui.hwnd);
    crate::apply_saved_settings(standalone);
}

unsafe extern "system" fn proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    if UI.is_null() {
        return DefWindowProcW(hwnd, msg, wp, lp);
    }
    let ui = &mut *UI;
    match msg {
        0x004E => {
            // WM_NOTIFY: tab selection changed.
            let hdr = &*(lp as *const NMHDR);
            if hdr.hwndFrom == ui.tab && hdr.code == 0xFFFF_FDD9 {
                let sel = SendMessageW(ui.tab, 0x130B, 0, 0) as usize; // TCM_GETCURSEL
                show_page(ui, sel);
            }
            0
        }
        0x0114 => {
            // WM_HSCROLL: slider moved -> update its edit box.
            if !ui.updating {
                if let Some(i) = ui.tracks.iter().position(|&t| t == lp as HWND) {
                    let pos = SendMessageW(ui.tracks[i], 0x0400, 0, 0) as i32; // TBM_GETPOS
                    ui.updating = true;
                    set_text(ui.edits[i], &pos.to_string());
                    ui.updating = false;
                }
            }
            0
        }
        WM_COMMAND => {
            let id = wp & 0xFFFF;
            let code = (wp >> 16) & 0xFFFF;
            match id {
                ID_OK => save_and_close(ui),
                ID_CANCEL => {
                    DestroyWindow(hwnd);
                }
                ID_DEFAULTS => {
                    let mut d = Config::parse(config::DEFAULT_CFG);
                    load_into_controls(ui, d);
                }
                i if (ID_EDIT..ID_EDIT + ROWS.len()).contains(&i) && code == 0x0300 && !ui.updating => {
                    // EN_CHANGE: edit box typed -> move the slider.
                    let n = i - ID_EDIT;
                    if n >= ui.edits.len() || n >= ui.tracks.len() {
                        return 0; // fired while the controls are still being created
                    }
                    if let Ok(v) = text_of(ui.edits[n]).trim().parse::<i32>() {
                        ui.updating = true;
                        SendMessageW(ui.tracks[n], 0x0405, 1, v.clamp(ROWS[n].1, ROWS[n].2) as isize);
                        ui.updating = false;
                    }
                }
                i if (ID_COLOR..ID_COLOR + 5).contains(&i) => pick_color(ui, i - ID_COLOR),
                i if (ID_FONT..ID_FONT + 2).contains(&i) => pick_font(ui, i - ID_FONT),
                _ => {}
            }
            0
        }
        0x0138 => {
            // WM_CTLCOLORSTATIC: paint the colour swatches.
            if let Some(i) = ui.swatches.iter().position(|&s| s == lp as HWND) {
                return ui.brushes[i] as LRESULT;
            }
            SetBkMode(wp as HDC, 1); // TRANSPARENT
            GetStockObject(0) as LRESULT // WHITE_BRUSH
        }
        WM_CLOSE => {
            DestroyWindow(hwnd);
            0
        }
        WM_DESTROY => {
            let standalone = ui.standalone;
            for &b in &ui.brushes {
                DeleteObject(b);
            }
            DeleteObject(ui.ui_font);
            drop(Box::from_raw(UI));
            UI = null_mut();
            if standalone {
                PostQuitMessage(0);
            }
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

/// Opens (or focuses) the settings window. In `standalone` mode closing it ends the process.
pub unsafe fn open(standalone: bool) {
    if !UI.is_null() {
        SetForegroundWindow((*UI).hwnd);
        return;
    }
    let icc = INITCOMMONCONTROLSEX {
        dwSize: std::mem::size_of::<INITCOMMONCONTROLSEX>() as u32,
        dwICC: 0x8 | 0x4, // ICC_TAB_CLASSES | ICC_BAR_CLASSES
    };
    InitCommonControlsEx(&icc);

    let hinst = GetModuleHandleW(null());
    let class = wide("BAVtrixSettings");
    let wc = WNDCLASSW {
        style: 0,
        lpfnWndProc: Some(proc),
        cbClsExtra: 0,
        cbWndExtra: 0,
        hInstance: hinst,
        hIcon: crate::atlas::app_icon(),
        hCursor: LoadCursorW(null_mut(), IDC_ARROW),
        hbrBackground: 6 as HBRUSH, // COLOR_WINDOW + 1: matches the white tab page
        lpszMenuName: null(),
        lpszClassName: class.as_ptr(),
    };
    RegisterClassW(&wc);

    let scale = GetDpiForSystem() as f32 / 96.0;
    let font_name = wide("Segoe UI");
    let ui_font = CreateFontW((-12.0 * scale) as i32, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, font_name.as_ptr());
    let (cw, ch) = ((552.0 * scale) as i32, (416.0 * scale) as i32);
    let mut rect = RECT { left: 0, top: 0, right: cw, bottom: ch };
    let style = WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    AdjustWindowRect(&mut rect, style, 0);
    let (sw, sh) = (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
    let (w, h) = (rect.right - rect.left, rect.bottom - rect.top);
    let hwnd = CreateWindowExW(
        0,
        class.as_ptr(),
        wide("BAVtrix — настройки").as_ptr(),
        style,
        (sw - w) / 2,
        (sh - h) / 2,
        w,
        h,
        null_mut(),
        null_mut(),
        hinst,
        null(),
    );
    let ui = Box::new(Ui {
        hwnd,
        tab: null_mut(),
        ui_font,
        scale,
        standalone,
        cfg: config::load(),
        pages: Vec::new(),
        tracks: Vec::new(),
        edits: Vec::new(),
        mono: null_mut(),
        rand: null_mut(),
        prio: null_mut(),
        swatches: Vec::new(),
        brushes: Vec::new(),
        mode: Vec::new(),
        blend: Vec::new(),
        font_labels: Vec::new(),
        charset: null_mut(),
        strings: null_mut(),
        updating: false,
    });
    UI = Box::into_raw(ui);
    let ui = &mut *UI;

    ui.tab = ctl(ui, "SysTabControl32", "", WS_TAB | WS_CLIPSIBLINGS, 0, (8, 8, 536, 354), 0);
    SendMessageW(ui.tab, WM_SETFONT, ui_font as WPARAM, 1);
    for (i, name) in TAB_NAMES.iter().enumerate() {
        let mut text = wide(name);
        let mut item: TCITEMW = std::mem::zeroed();
        item.mask = 1; // TCIF_TEXT
        item.pszText = text.as_mut_ptr();
        SendMessageW(ui.tab, 0x133E, i, &item as *const _ as isize); // TCM_INSERTITEMW
    }
    build(ui);
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
}
