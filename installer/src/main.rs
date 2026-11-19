#![windows_subsystem = "windows"]
//! Setup / uninstaller for BAVtrix. One self-contained exe, per-user install (no admin rights).
//!
//!   setup.exe                      installer window
//!   setup.exe /silent [/autostart] [/dir=PATH]   no window, default choices
//!   uninstall.exe /uninstall       removes BAVtrix (this exe is copied into the install folder)

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::System::Com::{CoInitializeEx, CoTaskMemFree};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Registry::*;
use windows_sys::Win32::UI::Controls::{InitCommonControlsEx, INITCOMMONCONTROLSEX};
use windows_sys::Win32::UI::HiDpi::GetDpiForSystem;
use windows_sys::Win32::UI::Shell::{SHBrowseForFolderW, SHGetPathFromIDListW, BROWSEINFOW};
use windows_sys::Win32::UI::WindowsAndMessaging::*;

static EXE: &[u8] = include_bytes!("../../release/1.0/bavtrix.exe");
static README: &[u8] = include_bytes!("../../release/1.0/README.txt");
static LICENSE: &[u8] = include_bytes!("../../release/1.0/LICENSE.TXT");

const NO_WINDOW: u32 = 0x0800_0000; // CREATE_NO_WINDOW
const UNINSTALL_KEY: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\BAVtrix";
const RUN_KEY: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const APP_NAME: &str = "BAVtrix";
const PUBLISHER: &str = "BArkVestan_Development";
const VERSION: &str = "1.0.0";

const ID_PATH: usize = 101;
const ID_BROWSE: usize = 102;
const ID_AUTOSTART: usize = 103;
const ID_DESKTOP: usize = 104;
const ID_STARTMENU: usize = 105;
const ID_LAUNCH: usize = 106;
const ID_INSTALL: usize = 1;
const ID_CANCEL: usize = 2;

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

#[derive(Clone)]
struct Options {
    dir: PathBuf,
    autostart: bool,
    desktop: bool,
    startmenu: bool,
    launch: bool,
}

// ---------- registry ----------

unsafe fn reg_set(subkey: &str, name: &str, value: &str) {
    let mut key: HKEY = null_mut();
    if RegCreateKeyExW(HKEY_CURRENT_USER, wide(subkey).as_ptr(), 0, null(), 0, KEY_WRITE, null(), &mut key, null_mut()) == 0 {
        let v = wide(value);
        RegSetValueExW(key, wide(name).as_ptr(), 0, REG_SZ, v.as_ptr() as *const u8, (v.len() * 2) as u32);
        RegCloseKey(key);
    }
}

unsafe fn reg_set_dword(subkey: &str, name: &str, value: u32) {
    let mut key: HKEY = null_mut();
    if RegCreateKeyExW(HKEY_CURRENT_USER, wide(subkey).as_ptr(), 0, null(), 0, KEY_WRITE, null(), &mut key, null_mut()) == 0 {
        RegSetValueExW(key, wide(name).as_ptr(), 0, REG_DWORD, &value as *const u32 as *const u8, 4);
        RegCloseKey(key);
    }
}

unsafe fn reg_get(subkey: &str, name: &str) -> Option<String> {
    let mut key: HKEY = null_mut();
    if RegOpenKeyExW(HKEY_CURRENT_USER, wide(subkey).as_ptr(), 0, KEY_READ, &mut key) != 0 {
        return None;
    }
    let mut buf = [0u16; 520];
    let mut size = (buf.len() * 2) as u32;
    let mut ty = 0u32;
    let rc = RegQueryValueExW(key, wide(name).as_ptr(), null(), &mut ty, buf.as_mut_ptr() as *mut u8, &mut size);
    RegCloseKey(key);
    if rc != 0 {
        return None;
    }
    let n = (size as usize / 2).min(buf.len());
    Some(String::from_utf16_lossy(&buf[..n]).trim_end_matches('\0').to_string())
}

unsafe fn reg_delete_value(subkey: &str, name: &str) {
    let mut key: HKEY = null_mut();
    if RegOpenKeyExW(HKEY_CURRENT_USER, wide(subkey).as_ptr(), 0, KEY_WRITE, &mut key) == 0 {
        RegDeleteValueW(key, wide(name).as_ptr());
        RegCloseKey(key);
    }
}

// ---------- helpers ----------

fn default_dir() -> PathBuf {
    unsafe {
        if let Some(loc) = reg_get(UNINSTALL_KEY, "InstallLocation") {
            if !loc.is_empty() {
                return PathBuf::from(loc);
            }
        }
    }
    if Path::new("D:\\").exists() {
        PathBuf::from("D:\\Programs\\BAVtrix")
    } else {
        let base = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| "C:\\".to_string());
        PathBuf::from(base).join("Programs").join("BAVtrix")
    }
}

fn ps_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}

fn run_powershell(script: &str) {
    let _ = Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script])
        .creation_flags(NO_WINDOW)
        .status();
}

fn kill_running() {
    let _ = Command::new("taskkill").args(["/f", "/im", "bavtrix.exe"]).creation_flags(NO_WINDOW).status();
    std::thread::sleep(std::time::Duration::from_millis(600));
}

// ---------- install ----------

fn install(o: &Options) -> Result<(), String> {
    kill_running();
    std::fs::create_dir_all(&o.dir).map_err(|e| format!("Не удалось создать папку {}: {e}", o.dir.display()))?;
    let exe_path = o.dir.join("bavtrix.exe");
    let write = |name: &str, data: &[u8]| -> Result<(), String> {
        std::fs::write(o.dir.join(name), data).map_err(|e| format!("Не удалось записать {name}: {e}"))
    };
    write("bavtrix.exe", EXE)?;
    write("bavtrix.scr", EXE)?;
    write("README.txt", README)?;
    write("LICENSE.TXT", LICENSE)?;
    let uninstaller = o.dir.join("uninstall.exe");
    if let Ok(me) = std::env::current_exe() {
        if me != uninstaller {
            let _ = std::fs::copy(&me, &uninstaller);
        }
    }

    unsafe {
        reg_set(UNINSTALL_KEY, "DisplayName", &format!("{APP_NAME} {VERSION}"));
        reg_set(UNINSTALL_KEY, "DisplayVersion", VERSION);
        reg_set(UNINSTALL_KEY, "Publisher", PUBLISHER);
        reg_set(UNINSTALL_KEY, "InstallLocation", &o.dir.to_string_lossy());
        reg_set(UNINSTALL_KEY, "DisplayIcon", &exe_path.to_string_lossy());
        reg_set(UNINSTALL_KEY, "UninstallString", &format!("\"{}\" /uninstall", uninstaller.display()));
        reg_set_dword(UNINSTALL_KEY, "NoModify", 1);
        reg_set_dword(UNINSTALL_KEY, "NoRepair", 1);
        if o.autostart {
            reg_set(RUN_KEY, APP_NAME, &format!("\"{}\"", exe_path.display()));
        } else {
            reg_delete_value(RUN_KEY, APP_NAME);
        }
    }

    if o.desktop || o.startmenu {
        let exe = ps_quote(&exe_path.to_string_lossy());
        let dir = ps_quote(&o.dir.to_string_lossy());
        let mut script = format!(
            "$w=New-Object -ComObject WScript.Shell; function L($p){{$s=$w.CreateShortcut($p);$s.TargetPath={exe};$s.WorkingDirectory={dir};$s.Description='BAVtrix';$s.Save()}};"
        );
        if o.desktop {
            script += "L (Join-Path ([Environment]::GetFolderPath('Desktop')) 'BAVtrix.lnk');";
        }
        if o.startmenu {
            script += "$d=Join-Path ([Environment]::GetFolderPath('Programs')) 'BAVtrix'; New-Item -ItemType Directory -Force $d | Out-Null; L (Join-Path $d 'BAVtrix.lnk');";
        }
        run_powershell(&script);
    }
    Ok(())
}

// ---------- uninstall ----------

unsafe fn uninstall() {
    let ask = MessageBoxW(
        null_mut(),
        wide("Удалить BAVtrix с этого компьютера?").as_ptr(),
        wide("BAVtrix — удаление").as_ptr(),
        0x24, // MB_YESNO | MB_ICONQUESTION
    );
    if ask != 6 {
        return;
    }
    kill_running();
    let dir = reg_get(UNINSTALL_KEY, "InstallLocation")
        .map(PathBuf::from)
        .or_else(|| std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf())));
    reg_delete_value(RUN_KEY, APP_NAME);
    RegDeleteKeyW(HKEY_CURRENT_USER, wide(UNINSTALL_KEY).as_ptr());
    run_powershell(
        "Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'BAVtrix.lnk') -ErrorAction SilentlyContinue;\
         Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'BAVtrix') -Recurse -Force -ErrorAction SilentlyContinue",
    );
    if let Some(dir) = dir {
        for f in ["bavtrix.exe", "bavtrix.scr", "README.txt", "LICENSE.TXT", "default.cfg", "crash.log", "debug.log", "debug.flag"] {
            let _ = std::fs::remove_file(dir.join(f));
        }
        // The running uninstaller cannot delete itself: let a detached cmd do it.
        // It retries for up to two minutes: the exe stays locked until this process has ended.
        let exe = dir.join("uninstall.exe");
        let cmd = format!(
            "(for /l %i in (1,1,120) do @if exist \"{exe}\" (del /f /q \"{exe}\" >nul 2>&1 & ping 127.0.0.1 -n 2 >nul)) & rmdir \"{dir}\" >nul 2>&1",
            exe = exe.display(),
            dir = dir.display()
        );
        // raw_arg: cmd.exe does not understand the backslash-escaped quotes Rust would add.
        let _ = Command::new("cmd.exe").raw_arg(format!("/s /c \"{cmd}\"")).creation_flags(NO_WINDOW).spawn();
    }
    MessageBoxW(null_mut(), wide("BAVtrix удалён.").as_ptr(), wide("BAVtrix").as_ptr(), 0x40);
}

// ---------- installer window ----------

struct Ui {
    path: HWND,
    autostart: HWND,
    desktop: HWND,
    startmenu: HWND,
    launch: HWND,
    done: Option<Options>,
}

static mut UI: *mut Ui = null_mut();

unsafe fn text_of(h: HWND) -> String {
    let n = GetWindowTextLengthW(h);
    let mut buf = vec![0u16; n as usize + 1];
    GetWindowTextW(h, buf.as_mut_ptr(), n + 1);
    String::from_utf16_lossy(&buf[..n as usize])
}

unsafe fn checked(h: HWND) -> bool {
    SendMessageW(h, 0x00F0, 0, 0) == 1 // BM_GETCHECK
}

unsafe fn browse(owner: HWND) -> Option<String> {
    let title = wide("Выберите папку для установки BAVtrix");
    let mut name = [0u16; 260];
    let bi = BROWSEINFOW {
        hwndOwner: owner,
        pidlRoot: null_mut(),
        pszDisplayName: name.as_mut_ptr(),
        lpszTitle: title.as_ptr(),
        ulFlags: 0x1 | 0x40, // BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
        lpfn: None,
        lParam: 0,
        iImage: 0,
    };
    let pidl = SHBrowseForFolderW(&bi);
    if pidl.is_null() {
        return None;
    }
    let mut path = [0u16; 520];
    let ok = SHGetPathFromIDListW(pidl, path.as_mut_ptr());
    CoTaskMemFree(pidl as *const _);
    if ok == 0 {
        return None;
    }
    let end = path.iter().position(|&c| c == 0).unwrap_or(0);
    Some(String::from_utf16_lossy(&path[..end]))
}

unsafe extern "system" fn proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        WM_COMMAND if !UI.is_null() => {
            let ui = &mut *UI;
            match wp & 0xFFFF {
                ID_BROWSE => {
                    if let Some(p) = browse(hwnd) {
                        let p = PathBuf::from(p);
                        // Picking a folder like D:\Programs installs into D:\Programs\BAVtrix.
                        let target = if p.file_name().map(|n| n.to_string_lossy().to_lowercase().contains("matrix")).unwrap_or(false) {
                            p
                        } else {
                            p.join("BAVtrix")
                        };
                        SetWindowTextW(ui.path, wide(&target.to_string_lossy()).as_ptr());
                    }
                }
                ID_INSTALL => {
                    let dir = text_of(ui.path).trim().to_string();
                    if dir.is_empty() {
                        MessageBoxW(hwnd, wide("Укажите папку установки.").as_ptr(), wide(APP_NAME).as_ptr(), 0x30);
                        return 0;
                    }
                    ui.done = Some(Options {
                        dir: PathBuf::from(dir),
                        autostart: checked(ui.autostart),
                        desktop: checked(ui.desktop),
                        startmenu: checked(ui.startmenu),
                        launch: checked(ui.launch),
                    });
                    DestroyWindow(hwnd);
                }
                ID_CANCEL => {
                    DestroyWindow(hwnd);
                }
                _ => {}
            }
            0
        }
        0x0138 => {
            // WM_CTLCOLORSTATIC / buttons: white background like the window.
            SetBkMode(wp as HDC, 1);
            GetStockObject(0) as LRESULT
        }
        WM_CLOSE => {
            DestroyWindow(hwnd);
            0
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

unsafe fn icon() -> HICON {
    LoadIconW(GetModuleHandleW(null()), 1 as *const u16)
}

unsafe fn run_wizard() -> Option<Options> {
    let icc = INITCOMMONCONTROLSEX { dwSize: std::mem::size_of::<INITCOMMONCONTROLSEX>() as u32, dwICC: 0x8 | 0x4 };
    InitCommonControlsEx(&icc);
    CoInitializeEx(null(), 2);

    let hinst = GetModuleHandleW(null());
    let class = wide("BAVtrixSetup");
    let wc = WNDCLASSW {
        style: 0,
        lpfnWndProc: Some(proc),
        cbClsExtra: 0,
        cbWndExtra: 0,
        hInstance: hinst,
        hIcon: icon(),
        hCursor: LoadCursorW(null_mut(), IDC_ARROW),
        hbrBackground: 6 as HBRUSH, // COLOR_WINDOW + 1
        lpszMenuName: null(),
        lpszClassName: class.as_ptr(),
    };
    RegisterClassW(&wc);

    let scale = GetDpiForSystem() as f32 / 96.0;
    let s = |v: i32| (v as f32 * scale) as i32;
    let face = wide("Segoe UI");
    let font = CreateFontW(-s(12), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, face.as_ptr());
    let big = CreateFontW(-s(22), 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 5, 0, face.as_ptr());

    let style = WS_CAPTION | WS_SYSMENU;
    let mut r = RECT { left: 0, top: 0, right: s(500), bottom: s(372) };
    AdjustWindowRect(&mut r, style, 0);
    let (w, h) = (r.right - r.left, r.bottom - r.top);
    let (sw, sh) = (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
    let hwnd = CreateWindowExW(
        0, class.as_ptr(), wide("Установка BAVtrix").as_ptr(), style,
        (sw - w) / 2, (sh - h) / 2, w, h, null_mut(), null_mut(), hinst, null(),
    );

    let make = |class: &str, text: &str, st: u32, ex: u32, x: i32, y: i32, cw: i32, ch: i32, id: usize, f: HFONT| -> HWND {
        let c = CreateWindowExW(
            ex, wide(class).as_ptr(), wide(text).as_ptr(), WS_CHILD | WS_VISIBLE | st,
            s(x), s(y), s(cw), s(ch), hwnd, id as *mut core::ffi::c_void, hinst, null(),
        );
        SendMessageW(c, WM_SETFONT, f as WPARAM, 1);
        c
    };
    const TAB: u32 = 0x0001_0000;
    const AUTOCHECK: u32 = 0x0003;

    make("STATIC", &format!("{APP_NAME} {VERSION}"), 0, 0, 24, 18, 450, 34, 0, big);
    make("STATIC", "Матричный дождь для рабочего стола Windows.\nАвтор: BArkVestan_Development", 0, 0, 26, 56, 450, 40, 0, font);
    make("STATIC", "Папка установки:", 0, 0, 26, 108, 300, 18, 0, font);
    let path = make("EDIT", &default_dir().to_string_lossy(), TAB | 0x0080, WS_EX_CLIENTEDGE, 26, 128, 330, 24, ID_PATH, font);
    make("BUTTON", "Обзор...", TAB, 0, 366, 127, 100, 26, ID_BROWSE, font);
    let autostart = make("BUTTON", "Запускать при входе в Windows (автозапуск)", TAB | AUTOCHECK, 0, 26, 172, 440, 22, ID_AUTOSTART, font);
    let desktop = make("BUTTON", "Ярлык на рабочем столе", TAB | AUTOCHECK, 0, 26, 200, 440, 22, ID_DESKTOP, font);
    let startmenu = make("BUTTON", "Ярлык в меню «Пуск»", TAB | AUTOCHECK, 0, 26, 228, 440, 22, ID_STARTMENU, font);
    let launch = make("BUTTON", "Запустить BAVtrix после установки", TAB | AUTOCHECK, 0, 26, 256, 440, 22, ID_LAUNCH, font);
    for c in [desktop, startmenu, launch] {
        SendMessageW(c, 0x00F1, 1, 0); // BM_SETCHECK
    }
    make("STATIC", "Установка только для текущего пользователя, права администратора не нужны.", 0, 0, 26, 292, 450, 20, 0, font);
    make("BUTTON", "Установить", TAB | 0x0001, 0, 270, 326, 100, 30, ID_INSTALL, font);
    make("BUTTON", "Отмена", TAB, 0, 380, 326, 90, 30, ID_CANCEL, font);

    let ui = Box::new(Ui { path, autostart, desktop, startmenu, launch, done: None });
    UI = Box::into_raw(ui);
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);

    let mut msg: MSG = std::mem::zeroed();
    while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
        if IsDialogMessageW(hwnd, &mut msg) == 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    let ui = Box::from_raw(UI);
    UI = null_mut();
    ui.done
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let has = |f: &str| args.iter().any(|a| a.eq_ignore_ascii_case(f));
    unsafe {
        if has("/uninstall") {
            uninstall();
            return;
        }
        let opts = if has("/silent") {
            let dir = args
                .iter()
                .find_map(|a| a.strip_prefix("/dir=").map(PathBuf::from))
                .unwrap_or_else(default_dir);
            Some(Options { dir, autostart: has("/autostart"), desktop: false, startmenu: false, launch: false })
        } else {
            run_wizard()
        };
        let Some(o) = opts else { return };
        match install(&o) {
            Ok(()) => {
                if !has("/silent") {
                    MessageBoxW(
                        null_mut(),
                        wide("BAVtrix установлен.").as_ptr(),
                        wide(APP_NAME).as_ptr(),
                        0x40,
                    );
                }
                if o.launch {
                    let _ = Command::new(o.dir.join("bavtrix.exe")).current_dir(&o.dir).spawn();
                }
            }
            Err(e) => {
                MessageBoxW(null_mut(), wide(&e).as_ptr(), wide("BAVtrix — ошибка").as_ptr(), 0x10);
            }
        }
    }
}
