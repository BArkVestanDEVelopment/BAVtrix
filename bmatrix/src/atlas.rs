//! Glyph coverage masks rendered once through GDI.

use crate::config::FontSpec;
use std::ptr::{null, null_mut};
use windows_sys::Win32::Graphics::Gdi::*;

pub struct Atlas {
    pub cw: usize,
    pub ch: usize,
    pub glyphs: Vec<Vec<u8>>,
}

/// The application icon embedded in the exe (resource 1), or the stock one as a fallback.
pub unsafe fn app_icon() -> windows_sys::Win32::UI::WindowsAndMessaging::HICON {
    use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows_sys::Win32::UI::WindowsAndMessaging::{LoadIconW, IDI_APPLICATION};
    let icon = LoadIconW(GetModuleHandleW(null()), 1 as *const u16);
    if icon.is_null() {
        LoadIconW(null_mut(), IDI_APPLICATION)
    } else {
        icon
    }
}

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Embeds the original ZMatrix "Matrix Code Font" as a process-private font.
pub fn register_embedded_font() {
    static FONT: &[u8] = include_bytes!("../assets/MatrixCodeFont.ttf");
    unsafe {
        let mut n = 0u32;
        AddFontMemResourceEx(FONT.as_ptr() as *const _, FONT.len() as u32, null(), &mut n);
    }
}

unsafe fn make_font(spec: &FontSpec, px: i32) -> HFONT {
    let name = wide(&spec.name);
    CreateFontW(
        -px.max(1),
        0,
        0,
        0,
        spec.weight,
        spec.italic as u32,
        0,
        0,
        1,
        0,
        0,
        4, // ANTIALIASED_QUALITY
        0,
        name.as_ptr(),
    )
}

/// Natural cell size of a font for the given characters.
pub fn measure(spec: &FontSpec, chars: &[char], px: i32) -> (usize, usize) {
    unsafe {
        let dc = CreateCompatibleDC(null_mut());
        let font = make_font(spec, px);
        let old = SelectObject(dc, font);
        let mut tm: TEXTMETRICW = std::mem::zeroed();
        GetTextMetricsW(dc, &mut tm);
        let mut w = 1i32;
        for &c in chars {
            let mut cw = 0i32;
            let code = if (c as u32) < 0x10000 { c as u32 } else { b'?' as u32 };
            if GetCharWidth32W(dc, code, code, &mut cw) != 0 {
                w = w.max(cw);
            }
        }
        SelectObject(dc, old);
        DeleteObject(font);
        DeleteDC(dc);
        (w as usize, (tm.tmHeight.max(1)) as usize)
    }
}

/// Renders every char into an `cw`x`ch` coverage mask, centred in the cell.
pub fn build(spec: &FontSpec, chars: &[char], px: i32, cw: usize, ch: usize) -> Atlas {
    unsafe {
        let dc = CreateCompatibleDC(null_mut());
        let mut bi: BITMAPINFO = std::mem::zeroed();
        bi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
        bi.bmiHeader.biWidth = cw as i32;
        bi.bmiHeader.biHeight = -(ch as i32);
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        let mut bits: *mut core::ffi::c_void = null_mut();
        let bmp = CreateDIBSection(dc, &bi, 0, &mut bits, null_mut(), 0);
        let old_bmp = SelectObject(dc, bmp);
        let font = make_font(spec, px);
        let old_font = SelectObject(dc, font);
        let mut tm: TEXTMETRICW = std::mem::zeroed();
        GetTextMetricsW(dc, &mut tm);
        SetBkColor(dc, 0);
        SetTextColor(dc, 0x00FF_FFFF);
        SetBkMode(dc, 2); // OPAQUE: black background under white text

        let mut glyphs = Vec::with_capacity(chars.len());
        for &c in chars {
            let px_slice = std::slice::from_raw_parts_mut(bits as *mut u32, cw * ch);
            px_slice.fill(0);
            let mut buf = [0u16; 2];
            let enc = c.encode_utf16(&mut buf);
            let mut gw = 0i32;
            let code = if (c as u32) < 0x10000 { c as u32 } else { b'?' as u32 };
            GetCharWidth32W(dc, code, code, &mut gw);
            let x = ((cw as i32 - gw) / 2).max(0);
            let y = ((ch as i32 - tm.tmHeight) / 2).max(0);
            TextOutW(dc, x, y, enc.as_ptr(), enc.len() as i32);
            GdiFlush();
            let px_slice = std::slice::from_raw_parts(bits as *const u32, cw * ch);
            glyphs.push(px_slice.iter().map(|p| (p & 0xFF) as u8).collect());
        }
        SelectObject(dc, old_font);
        DeleteObject(font);
        SelectObject(dc, old_bmp);
        DeleteObject(bmp);
        DeleteDC(dc);
        Atlas { cw, ch, glyphs }
    }
}
