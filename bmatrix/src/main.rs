#![windows_subsystem = "windows"]
//! BAVtrix: digital rain for the Windows desktop (high-DPI, multi-monitor).
//!
//!   bavtrix.exe        desktop overlay (click-through, tray icon to exit)
//!   bavtrix.scr /s     screensaver
//!   bavtrix.scr /c     open default.cfg for editing
//!   bavtrix.scr /p     preview (ignored)

mod atlas;
mod config;
mod render;
mod settings;
mod sim;

use config::Config;
use render::{Mode, Renderer};
use sim::{Sim, SimParams};
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::Graphics::GdiPlus::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Diagnostics::Debug::{ReadProcessMemory, WriteProcessMemory};
use windows_sys::Win32::System::Memory::*;
use windows_sys::Win32::System::SystemInformation::GetTickCount64;
use windows_sys::Win32::System::Threading::*;
use windows_sys::Win32::UI::HiDpi::*;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const TIMER_ID: usize = 1;
const FRAME_MS: u32 = 33;
const WM_TRAY: u32 = WM_APP + 1;
const CMD_EXIT: usize = 1;
const CMD_CONFIG: usize = 2;

struct App {
    mode: Mode,
    screensaver: bool,
    cfg: Config,
    sim: Sim,
    renderer: Renderer,
    memdc: HDC,
    bits: *mut u32,
    /// Transparent layer above the desktop icons (null when unavailable).
    front: HWND,
    /// The desktop icon list (SysListView32) behind the front layer.
    list: HWND,
    front_dc: HDC,
    front_bits: *mut u32,
    w: usize,
    h: usize,
    vx: i32,
    vy: i32,
    last_tick: u64,
    born: u64,
    start_mouse: Option<(i32, i32)>,
}

static mut APP: *mut App = null_mut();

fn priority_class(name: &str) -> u32 {
    let n = name.to_uppercase();
    if n.contains("IDLE") {
        IDLE_PRIORITY_CLASS
    } else if n.contains("BELOW") {
        BELOW_NORMAL_PRIORITY_CLASS
    } else if n.contains("ABOVE") {
        ABOVE_NORMAL_PRIORITY_CLASS
    } else if n.contains("HIGH") {
        HIGH_PRIORITY_CLASS
    } else {
        NORMAL_PRIORITY_CLASS
    }
}

/// Called after the settings window saved `default.cfg`: restarts the running rain so the
/// new settings take effect (from the tray: this process; from `/c`: the running instance).
pub unsafe fn apply_saved_settings(standalone: bool) {
    let Some(exe) = std::env::current_exe().ok() else { return };
    let sibling = exe.with_file_name("bavtrix.exe");
    let target = if sibling.exists() { sibling } else { exe };
    if standalone {
        let ctl = FindWindowExW(HWND_MESSAGE, null_mut(), atlas::wide("BAVtrixCtl").as_ptr(), null());
        if ctl.is_null() {
            return;
        }
        PostMessageW(ctl, WM_CLOSE, 0, 0);
        Sleep(700);
        let _ = std::process::Command::new(target).spawn();
    } else {
        let _ = std::process::Command::new(target).spawn();
        PostQuitMessage(0);
    }
}

unsafe extern "system" fn ctl_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    if msg == WM_CLOSE {
        PostQuitMessage(0);
        return 0;
    }
    DefWindowProcW(hwnd, msg, wp, lp)
}

/// Appends a line to `debug.log` next to the exe, only when a `debug.flag` file exists there.
fn debug_log(msg: &str) {
    use std::io::Write;
    let Some(dir) = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf())) else { return };
    if !dir.join("debug.flag").exists() {
        return;
    }
    let file = std::fs::OpenOptions::new().create(true).append(true).open(dir.join("debug.log"));
    let _ = file.map(|mut f| writeln!(f, "{msg}"));
}

unsafe extern "system" fn collect_monitor(_: HMONITOR, _: HDC, r: *mut RECT, lp: LPARAM) -> BOOL {
    (*(lp as *mut Vec<RECT>)).push(*r);
    1
}

/// Loads the current desktop wallpaper (without windows or icons), scaled to cover each
/// monitor. Returns None for a solid-colour desktop or if the image can't be read.
unsafe fn load_wallpaper(vx: i32, vy: i32, w: usize, h: usize) -> Option<Vec<u32>> {
    let mut path = [0u16; 520];
    SystemParametersInfoW(SPI_GETDESKWALLPAPER, path.len() as u32, path.as_mut_ptr() as *mut _, 0);
    let end = path.iter().position(|&c| c == 0).unwrap_or(0);
    debug_log(&format!("wallpaper path: {}", String::from_utf16_lossy(&path[..end])));
    if path[0] == 0 {
        return None;
    }

    let mut token = 0usize;
    let mut input: GdiplusStartupInput = std::mem::zeroed();
    input.GdiplusVersion = 1;
    if GdiplusStartup(&mut token, &input, null_mut()) != 0 {
        return None;
    }
    let mut gp: *mut GpBitmap = null_mut();
    let mut result = None;
    if GdipCreateBitmapFromFile(path.as_ptr(), &mut gp) == 0 {
        let (mut iw, mut ih) = (0u32, 0u32);
        GdipGetImageWidth(gp as *mut GpImage, &mut iw);
        GdipGetImageHeight(gp as *mut GpImage, &mut ih);
        let mut hbm: HBITMAP = null_mut();
        if iw > 0 && ih > 0 && GdipCreateHBITMAPFromBitmap(gp, &mut hbm, 0) == 0 {
            let screen = GetDC(null_mut());
            let src = CreateCompatibleDC(screen);
            let old_src = SelectObject(src, hbm);

            let dst = CreateCompatibleDC(screen);
            let mut bi: BITMAPINFO = std::mem::zeroed();
            bi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
            bi.bmiHeader.biWidth = w as i32;
            bi.bmiHeader.biHeight = -(h as i32);
            bi.bmiHeader.biPlanes = 1;
            bi.bmiHeader.biBitCount = 32;
            let mut bits: *mut core::ffi::c_void = null_mut();
            let dib = CreateDIBSection(dst, &bi, 0, &mut bits, null_mut(), 0);
            let old_dst = SelectObject(dst, dib);
            std::slice::from_raw_parts_mut(bits as *mut u32, w * h).fill(0);
            SetStretchBltMode(dst, 4); // HALFTONE

            let mut monitors: Vec<RECT> = Vec::new();
            EnumDisplayMonitors(null_mut(), null(), Some(collect_monitor), &mut monitors as *mut _ as LPARAM);
            for m in &monitors {
                let (mw, mh) = ((m.right - m.left) as f32, (m.bottom - m.top) as f32);
                let k = (mw / iw as f32).max(mh / ih as f32);
                let (sw, sh) = (mw / k, mh / k);
                let (sx, sy) = ((iw as f32 - sw) / 2.0, (ih as f32 - sh) / 2.0);
                StretchBlt(
                    dst, m.left - vx, m.top - vy, mw as i32, mh as i32,
                    src, sx as i32, sy as i32, sw as i32, sh as i32, SRCCOPY,
                );
            }
            GdiFlush();
            result = Some(std::slice::from_raw_parts(bits as *const u32, w * h).to_vec());

            SelectObject(dst, old_dst);
            DeleteObject(dib);
            DeleteDC(dst);
            SelectObject(src, old_src);
            DeleteDC(src);
            DeleteObject(hbm);
            ReleaseDC(null_mut(), screen);
        }
        GdipDisposeImage(gp as *mut GpImage);
    }
    GdiplusShutdown(token);
    result
}

unsafe extern "system" fn find_icon_host(hwnd: HWND, lp: LPARAM) -> BOOL {
    let defview = FindWindowExW(hwnd, null_mut(), atlas::wide("SHELLDLL_DefView").as_ptr(), null());
    if !defview.is_null() {
        *(lp as *mut HWND) = hwnd;
    }
    1
}

/// Returns (icon host, wallpaper host) of the desktop: the window that holds the icon list
/// (Progman, or a WorkerW on some builds) and the WorkerW that sits behind the icons.
unsafe fn desktop_layers() -> (HWND, HWND) {
    let progman = FindWindowW(atlas::wide("Progman").as_ptr(), null());
    if progman.is_null() {
        return (null_mut(), null_mut());
    }
    let mut res = 0usize;
    SendMessageTimeoutW(progman, 0x052C, 0xD, 0x1, SMTO_NORMAL, 1000, &mut res);

    let mut icons: HWND = null_mut();
    if !FindWindowExW(progman, null_mut(), atlas::wide("SHELLDLL_DefView").as_ptr(), null()).is_null() {
        icons = progman;
    } else {
        EnumWindows(Some(find_icon_host), &mut icons as *mut _ as LPARAM);
    }
    if icons.is_null() {
        return (null_mut(), null_mut());
    }
    let worker_name = atlas::wide("WorkerW");
    // Classic layout: the next top-level WorkerW after the icon host is the wallpaper layer.
    let mut wallpaper = FindWindowExW(null_mut(), icons, worker_name.as_ptr(), null());
    if wallpaper.is_null() {
        // Windows 11 24H2+: it is a child of Progman.
        wallpaper = FindWindowExW(progman, null_mut(), worker_name.as_ptr(), null());
    }
    (icons, wallpaper)
}

unsafe fn make_dib(w: usize, h: usize) -> (HDC, *mut u32) {
    let dc = CreateCompatibleDC(null_mut());
    let mut bi: BITMAPINFO = std::mem::zeroed();
    bi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
    bi.bmiHeader.biWidth = w as i32;
    bi.bmiHeader.biHeight = -(h as i32);
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    let mut bits: *mut core::ffi::c_void = null_mut();
    let bmp = CreateDIBSection(dc, &bi, 0, &mut bits, null_mut(), 0);
    SelectObject(dc, bmp);
    (dc, bits as *mut u32)
}

unsafe fn present(app: &App, hwnd: HWND) {
    match app.mode {
        Mode::Overlay => {
            let screen = GetDC(null_mut());
            let pt = POINT { x: app.vx, y: app.vy };
            let size = SIZE { cx: app.w as i32, cy: app.h as i32 };
            let src = POINT { x: 0, y: 0 };
            let blend = BLENDFUNCTION { BlendOp: 0, BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: 1 };
            UpdateLayeredWindow(hwnd, screen, &pt, &size, app.memdc, &src, 0, &blend, 2);
            ReleaseDC(null_mut(), screen);
        }
        Mode::Opaque => {
            let dc = GetDC(hwnd);
            BitBlt(dc, 0, 0, app.w as i32, app.h as i32, app.memdc, 0, 0, SRCCOPY);
            ReleaseDC(hwnd, dc);
        }
    }
}

unsafe fn tick(hwnd: HWND) {
    let app = &mut *APP;
    let now = GetTickCount64();
    if now - app.last_tick > 70 {
        debug_log(&format!("slow frame: {} ms since the previous one", now - app.last_tick));
    }
    let dt = (now - app.last_tick).min(250) as f32;
    app.last_tick = now;
    let t0 = std::time::Instant::now();
    app.sim.advance(dt);
    let t_sim = t0.elapsed();
    let n = app.w * app.h;
    if app.front.is_null() {
        let buf = std::slice::from_raw_parts_mut(app.bits, n);
        app.renderer.draw(&app.cfg, &app.sim, buf, app.w, app.h, false);
        present(app, hwnd);
        return;
    }
    // The front layer is an opaque picture of the rain: it hides the desktop icons completely.
    // It is rendered directly; the back layer is only needed behind the holes of revealed icons.
    let front = std::slice::from_raw_parts_mut(app.front_bits, n);
    let t1 = std::time::Instant::now();
    app.renderer.draw(&app.cfg, &app.sim, front, app.w, app.h, false);
    let t_draw = t1.elapsed();
    // The rectangles come from a worker thread: asking Explorer can block while it is busy
    // (for example during a rubber-band selection), and the rain must not wait for it.
    let rects = ICONS.lock().ok().map(|g| g.clone()).unwrap_or_default();
    // Revealed icons show through holes. The persistent frame stays intact: the pixels under
    // each hole are copied to the back layer, zeroed for the presentation and restored after it.
    let (w, h) = (app.w as i32, app.h as i32);
    let mut saved: Vec<(usize, Vec<u32>)> = Vec::new();
    if !rects.is_empty() {
        let back = std::slice::from_raw_parts_mut(app.bits, n);
        let wdc = GetDC(hwnd);
        for r in &rects {
            let (x0, x1) = ((r[0] - app.vx).clamp(0, w), (r[2] - app.vx).clamp(0, w));
            let (y0, y1) = ((r[1] - app.vy).clamp(0, h), (r[3] - app.vy).clamp(0, h));
            if x1 <= x0 || y1 <= y0 {
                continue;
            }
            let len = (x1 - x0) as usize;
            for y in y0..y1 {
                let o = y as usize * app.w + x0 as usize;
                back[o..o + len].copy_from_slice(&front[o..o + len]);
                saved.push((o, front[o..o + len].to_vec()));
                front[o..o + len].fill(0);
            }
            BitBlt(wdc, x0, y0, x1 - x0, y1 - y0, app.memdc, x0, y0, SRCCOPY);
        }
        ReleaseDC(hwnd, wdc);
    }
    let screen = GetDC(null_mut());
    let size = SIZE { cx: app.w as i32, cy: app.h as i32 };
    let src = POINT { x: 0, y: 0 };
    let blend = BLENDFUNCTION { BlendOp: 0, BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: 1 };
    let t2 = std::time::Instant::now();
    UpdateLayeredWindow(app.front, screen, null(), &size, app.front_dc, &src, 0, &blend, 2);
    ReleaseDC(null_mut(), screen);
    let t_present = t2.elapsed();
    for (o, v) in saved {
        front[o..o + v.len()].copy_from_slice(&v);
    }
    static mut FRAMES: u32 = 0;
    static mut ACC: [f32; 3] = [0.0; 3];
    ACC[0] += t_sim.as_secs_f32() * 1000.0;
    ACC[1] += t_draw.as_secs_f32() * 1000.0;
    ACC[2] += t_present.as_secs_f32() * 1000.0;
    FRAMES += 1;
    if FRAMES == 60 {
        debug_log(&format!(
            "avg per frame over 60: sim {:.2} ms, draw {:.2} ms, present {:.2} ms; last frame: repainted cells {}, icon holes {}, cells total {}",
            ACC[0] / 60.0, ACC[1] / 60.0, ACC[2] / 60.0,
            if app.renderer.repainted == usize::MAX { "ALL (full redraw)".to_string() } else { app.renderer.repainted.to_string() },
            rects.len(), app.sim.cells.len()
        ));
        FRAMES = 0;
        ACC = [0.0; 3];
    }
}

/// Latest screen rectangles (left, top, right, bottom) of the icons that must stay visible.
static ICONS: std::sync::Mutex<Vec<[i32; 4]>> = std::sync::Mutex::new(Vec::new());

/// Finds the desktop icon list (SysListView32) inside the window that hosts the icons.
unsafe fn find_icon_list(icon_host: HWND) -> HWND {
    let defview = FindWindowExW(icon_host, null_mut(), atlas::wide("SHELLDLL_DefView").as_ptr(), null());
    if defview.is_null() {
        return null_mut();
    }
    FindWindowExW(defview, null_mut(), atlas::wide("SysListView32").as_ptr(), null())
}

/// Screen rectangles of the desktop icons that must stay visible: the icon under the cursor
/// and every selected icon (so a rubber-band selection reveals the icons it covers). The icon
/// list lives in Explorer, so item data is fetched through its memory.
unsafe fn visible_icons(list: HWND) -> Vec<RECT> {
    let mut out = Vec::new();
    if list.is_null() {
        return out;
    }
    let mut pid = 0u32;
    GetWindowThreadProcessId(list, &mut pid);
    let proc = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE, 0, pid);
    if proc.is_null() {
        return out;
    }
    let mem = VirtualAllocEx(proc, null(), 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if !mem.is_null() {
        let send = |msg: u32, wp: WPARAM, lp: LPARAM| -> Option<isize> {
            let mut res = 0usize;
            let ok = SendMessageTimeoutW(list, msg, wp, lp, SMTO_ABORTIFHUNG, 50, &mut res);
            (ok != 0).then_some(res as isize)
        };
        let rect_mem = (mem as usize + 64) as *mut core::ffi::c_void;
        let item_rect = |item: i32| -> Option<RECT> {
            let seed = RECT { left: 0, top: 0, right: 0, bottom: 0 }; // left = LVIR_BOUNDS
            WriteProcessMemory(proc, rect_mem, &seed as *const _ as *const _, 16, null_mut());
            if send(0x100E, item as WPARAM, rect_mem as LPARAM) != Some(1) {
                return None; // LVM_GETITEMRECT failed
            }
            let mut r = RECT { left: 0, top: 0, right: 0, bottom: 0 };
            ReadProcessMemory(proc, rect_mem, &mut r as *mut _ as *mut _, 16, null_mut());
            let mut tl = POINT { x: r.left, y: r.top };
            let mut br = POINT { x: r.right, y: r.bottom };
            ClientToScreen(list, &mut tl);
            ClientToScreen(list, &mut br);
            Some(RECT { left: tl.x, top: tl.y, right: br.x, bottom: br.y })
        };

        // The icon under the cursor.
        let mut pt = POINT { x: 0, y: 0 };
        GetCursorPos(&mut pt);
        if WindowFromPoint(pt) == list {
            let mut client = pt;
            ScreenToClient(list, &mut client);
            // LVHITTESTINFO { POINT pt; UINT flags; int iItem; int iSubItem; int iGroup }
            let info: [i32; 6] = [client.x, client.y, 0, -1, 0, 0];
            WriteProcessMemory(proc, mem, info.as_ptr() as *const _, 24, null_mut());
            let item = send(0x1012, 0, mem as LPARAM).map(|v| v as i32).unwrap_or(-1); // LVM_HITTEST
            if item >= 0 {
                out.extend(item_rect(item));
            }
        }

        // Selected icons.
        let mut prev = -1i32;
        for _ in 0..400 {
            // LVM_GETNEXTITEM with LVNI_SELECTED
            let next = send(0x100C, prev as isize as WPARAM, 2).map(|v| v as i32).unwrap_or(-1);
            if next < 0 {
                break;
            }
            out.extend(item_rect(next));
            prev = next;
        }
        VirtualFreeEx(proc, mem, 0, MEM_RELEASE);
    }
    CloseHandle(proc);
    out
}

unsafe fn show_tray_menu(hwnd: HWND) {
    let menu = CreatePopupMenu();
    AppendMenuW(menu, 0, CMD_CONFIG, atlas::wide("Настройки...").as_ptr());
    AppendMenuW(menu, 0, CMD_EXIT, atlas::wide("Выход").as_ptr());
    SetMenuDefaultItem(menu, CMD_CONFIG as u32, 0);
    let mut pt = POINT { x: 0, y: 0 };
    GetCursorPos(&mut pt);
    SetForegroundWindow(hwnd);
    TrackPopupMenu(menu, 2, pt.x, pt.y, 0, hwnd, null());
    DestroyMenu(menu);
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    let opaque = !APP.is_null() && (*APP).screensaver;
    match msg {
        WM_TIMER if !APP.is_null() => {
            tick(hwnd);
            0
        }
        WM_ERASEBKGND => 1,
        WM_PAINT => {
            let mut ps: PAINTSTRUCT = std::mem::zeroed();
            BeginPaint(hwnd, &mut ps);
            if !APP.is_null() && (*APP).mode == Mode::Opaque {
                present(&*APP, hwnd);
            }
            EndPaint(hwnd, &ps);
            0
        }
        WM_TRAY if lp as u32 == WM_RBUTTONUP => {
            show_tray_menu(hwnd);
            0
        }
        WM_TRAY if lp as u32 == WM_LBUTTONDBLCLK => {
            settings::open(false);
            0
        }
        WM_COMMAND if wp & 0xFFFF == CMD_CONFIG => {
            settings::open(false);
            0
        }
        WM_COMMAND if wp & 0xFFFF == CMD_EXIT => {
            DestroyWindow(hwnd);
            0
        }
        WM_KEYDOWN | WM_LBUTTONDOWN | WM_RBUTTONDOWN | WM_MBUTTONDOWN if opaque => {
            debug_log(&format!("screensaver exit: input message {msg:#x}"));
            DestroyWindow(hwnd);
            0
        }
        WM_MOUSEMOVE if opaque => {
            let (x, y) = ((lp & 0xFFFF) as i16 as i32, ((lp >> 16) & 0xFFFF) as i16 as i32);
            let app = &mut *APP;
            match app.start_mouse {
                None => app.start_mouse = Some((x, y)),
                // Ignore the first second and small jitter, like regular screensavers.
                Some((sx, sy)) if (x - sx).abs() + (y - sy).abs() > 10 && GetTickCount64() - app.born > 1000 => {
                    debug_log(&format!("screensaver exit: mouse moved ({sx},{sy}) -> ({x},{y})"));
                    DestroyWindow(hwnd);
                }
                _ => {}
            }
            0
        }
        WM_SETCURSOR if opaque => {
            SetCursor(null_mut());
            1
        }
        WM_DESTROY => {
            let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
            nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            nid.hWnd = hwnd;
            nid.uID = 1;
            Shell_NotifyIconW(NIM_DELETE, &nid);
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

fn main() {
    // Panics abort the process; keep the reason in `crash.log` next to the exe.
    std::panic::set_hook(Box::new(|info| {
        if let Some(dir) = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf())) {
            let _ = std::fs::write(dir.join("crash.log"), format!("{info}\r\n"));
        }
    }));
    let args: Vec<String> = std::env::args().skip(1).map(|a| a.to_lowercase()).collect();
    let flag = args.first().map(|a| a.trim_start_matches(['/', '-']).chars().next().unwrap_or(' '));
    unsafe {
        match flag {
            Some('p') => return,
            Some('c') => {
                SetProcessDpiAwarenessContext(-4isize as _);
                atlas::register_embedded_font();
                settings::open(true);
                let mut msg: MSG = std::mem::zeroed();
                while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
                    if IsDialogMessageW(GetAncestor(msg.hwnd, GA_ROOT), &mut msg) == 0 {
                        TranslateMessage(&msg);
                        DispatchMessageW(&msg);
                    }
                }
                return;
            }
            _ => {}
        }
        let opaque = flag == Some('s');

        SetProcessDpiAwarenessContext(-4isize as _); // PER_MONITOR_AWARE_V2
        let cfg = config::load();
        SetPriorityClass(GetCurrentProcess(), priority_class(&cfg.priority));
        atlas::register_embedded_font();

        let vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        let vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        let w = GetSystemMetrics(SM_CXVIRTUALSCREEN).max(1) as usize;
        let h = GetSystemMetrics(SM_CYVIRTUALSCREEN).max(1) as usize;

        // The original font sizes assume ~96 DPI / 1024x768. Scale them to the primary
        // monitor's DPI and resolution so the rain looks the same on 4K screens.
        let dpi_scale = GetDpiForSystem() as f32 / 96.0;
        let res_scale = GetSystemMetrics(SM_CYSCREEN) as f32 / 1080.0;
        let scale = dpi_scale.max(res_scale).max(1.0);
        let px = ((cfg.text.height.abs() as f32) * scale).round() as i32;
        let spx = ((cfg.special_font.height.abs() as f32) * scale).round() as i32;

        let mut special_chars: Vec<char> = Vec::new();
        for s in &cfg.special_strings {
            for &c in s {
                if !special_chars.contains(&c) {
                    special_chars.push(c);
                }
            }
        }
        let (cw, ch) = atlas::measure(&cfg.text, &cfg.charset, px);
        let main = atlas::build(&cfg.text, &cfg.charset, px, cw, ch);
        let special = atlas::build(&cfg.special_font, &special_chars, spx, cw, ch);

        let special_strings = cfg
            .special_strings
            .iter()
            .map(|s| s.iter().map(|c| special_chars.iter().position(|x| x == c).unwrap() as u16).collect())
            .collect();
        let seed = GetTickCount64() ^ ((GetCurrentProcessId() as u64) << 32);
        let sim = Sim::new(
            w / cw,
            h / ch,
            SimParams {
                max_stream: cfg.max_stream,
                speed_variance: cfg.speed_variance,
                monotonous: cfg.monotonous_cleanup,
                back_trace: cfg.back_trace,
                randomized: cfg.randomized_cleanup,
                leading: cfg.leading,
                space_pad: cfg.space_pad,
                refresh_ms: cfg.refresh_ms as f32,
                special_probability: cfg.special_probability,
                spawn_rate: cfg.spawn_rate,
                flicker: cfg.flicker,
                head_flicker: cfg.head_flicker,
                trail_min: cfg.trail_min,
                trail_max: cfg.trail_max,
                charset_len: cfg.charset.len(),
                special_strings,
            },
            seed,
        );

        let wallpaper = if cfg.bg_bitmap { load_wallpaper(vx, vy, w, h) } else { None };
        debug_log(&format!(
            "wallpaper loaded: {} (bg_bitmap={}), brightest pixel: {:#010x}",
            wallpaper.is_some(),
            cfg.bg_bitmap,
            wallpaper.as_ref().map(|w| w.iter().copied().max().unwrap_or(0)).unwrap_or(0)
        ));
        // At Windows start (autostart) Explorer may not have created its desktop windows yet:
        // wait up to 30 s instead of falling back to the topmost overlay.
        let (icon_host, worker) = if opaque {
            (null_mut(), null_mut())
        } else {
            let mut layers = desktop_layers();
            for _ in 0..60 {
                if !layers.0.is_null() && !layers.1.is_null() && !find_icon_list(layers.0).is_null() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(500));
                layers = desktop_layers();
            }
            layers
        };
        let embedded = !worker.is_null() && !icon_host.is_null();

        let (memdc, bits) = make_dib(w, h);
        let (front_dc, front_bits) = if embedded { make_dib(w, h) } else { (null_mut(), null_mut()) };

        let mode = if opaque || embedded { Mode::Opaque } else { Mode::Overlay };
        let app = Box::new(App {
            mode,
            screensaver: opaque,
            cfg,
            sim,
            renderer: Renderer { main, special, mode, wallpaper, cache: Vec::new(), valid: false, repainted: 0 },
            memdc,
            bits,
            front: null_mut(),
            list: if embedded { find_icon_list(icon_host) } else { null_mut() },
            front_dc,
            front_bits,
            w,
            h,
            vx,
            vy,
            last_tick: GetTickCount64(),
            born: GetTickCount64(),
            start_mouse: None,
        });
        APP = Box::into_raw(app);
        if embedded && !(*APP).list.is_null() {
            let list = (*APP).list as usize;
            std::thread::spawn(move || loop {
                let rects = visible_icons(list as HWND);
                if let Some(mut g) = ICONS.lock().ok() {
                    *g = rects.iter().map(|r| [r.left, r.top, r.right, r.bottom]).collect();
                }
                std::thread::sleep(std::time::Duration::from_millis(15));
            });
        }

        let hinst = GetModuleHandleW(null());
        let class = atlas::wide("BAVtrixWindow");
        let wc = WNDCLASSW {
            style: 0,
            lpfnWndProc: Some(wnd_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: hinst,
            hIcon: atlas::app_icon(),
            hCursor: LoadCursorW(null_mut(), IDC_ARROW),
            hbrBackground: null_mut(),
            lpszMenuName: null(),
            lpszClassName: class.as_ptr(),
        };
        RegisterClassW(&wc);

        let ex = if opaque {
            WS_EX_TOPMOST
        } else if embedded {
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
        } else {
            WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
        };
        let hwnd = CreateWindowExW(
            ex,
            class.as_ptr(),
            atlas::wide("BAVtrix").as_ptr(),
            WS_POPUP | WS_VISIBLE,
            vx,
            vy,
            w as i32,
            h as i32,
            null_mut(),
            null_mut(),
            hinst,
            null(),
        );
        if hwnd.is_null() {
            return;
        }
        if embedded {
            // Re-parent into the desktop so the rain covers icons but stays under windows.
            // Back layer: black rain behind the icons, replacing the wallpaper.
            SetWindowLongPtrW(hwnd, GWL_STYLE, (WS_CHILD | WS_VISIBLE) as isize);
            SetParent(hwnd, worker);
            let mut origin = POINT { x: vx, y: vy };
            ScreenToClient(worker, &mut origin);
            SetWindowPos(hwnd, HWND_TOP, origin.x, origin.y, w as i32, h as i32, SWP_NOACTIVATE | SWP_SHOWWINDOW);

            // Front layer: the same glyphs on a transparent layer above the icons,
            // so icons are covered gradually as the streams pass over them.
            let front = CreateWindowExW(
                WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                class.as_ptr(),
                atlas::wide("BAVtrix front").as_ptr(),
                WS_POPUP,
                vx,
                vy,
                w as i32,
                h as i32,
                null_mut(),
                null_mut(),
                hinst,
                null(),
            );
            if !front.is_null() {
                SetWindowLongPtrW(front, GWL_STYLE, (WS_CHILD | WS_VISIBLE) as isize);
                SetParent(front, icon_host);
                let mut origin = POINT { x: vx, y: vy };
                ScreenToClient(icon_host, &mut origin);
                SetWindowPos(front, HWND_TOP, origin.x, origin.y, w as i32, h as i32, SWP_NOACTIVATE | SWP_SHOWWINDOW);
                (*APP).front = front;
            }
        }

        if opaque {
            ShowCursor(0);
        } else {
            let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
            nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            nid.hWnd = hwnd;
            nid.uID = 1;
            nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
            nid.uCallbackMessage = WM_TRAY;
            nid.hIcon = atlas::app_icon();
            for (i, c) in "BAVtrix".encode_utf16().enumerate() {
                nid.szTip[i] = c;
            }
            Shell_NotifyIconW(NIM_ADD, &nid);

            // Hidden message-only window: lets `/c` find this instance and ask it to restart.
            let ctl_class = atlas::wide("BAVtrixCtl");
            let cwc = WNDCLASSW {
                style: 0,
                lpfnWndProc: Some(ctl_proc),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: hinst,
                hIcon: null_mut(),
                hCursor: null_mut(),
                hbrBackground: null_mut(),
                lpszMenuName: null(),
                lpszClassName: ctl_class.as_ptr(),
            };
            RegisterClassW(&cwc);
            CreateWindowExW(0, ctl_class.as_ptr(), null(), 0, 0, 0, 0, 0, HWND_MESSAGE, null_mut(), hinst, null());
        }

        SetTimer(hwnd, TIMER_ID, FRAME_MS, None);
        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            if IsDialogMessageW(GetAncestor(msg.hwnd, GA_ROOT), &mut msg) == 0 {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        if !opaque {
            let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
            nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            nid.hWnd = hwnd;
            nid.uID = 1;
            Shell_NotifyIconW(NIM_DELETE, &nid);
        }
        if opaque {
            ShowCursor(1);
        }
    }
}

