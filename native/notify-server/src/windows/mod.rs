//! Windows-specific code to set file stream modes. Used to set
//! the mode to `_O_BINARY` to avoid translation and insertion
//! of carriage return characters in the standard streams.
//!
//! Source: https://gist.github.com/leiless/994d161a1d254e267a6d84ad5bf0895a

#[cfg(target_os = "windows")]
unsafe extern "C" {
    // https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/setmode?view=msvc-170
    // https://learn.microsoft.com/en-us/previous-versions/visualstudio/visual-studio-6.0/aa298581(v=vs.60)
    fn _setmode(fd: std::os::raw::c_int, mode: std::os::raw::c_int) -> std::os::raw::c_int;
    // https://learn.microsoft.com/en-us/previous-versions/visualstudio/visual-studio-2010/wwfcfxas(v=vs.100)
    fn _get_errno(p_value: *mut std::os::raw::c_int) -> std::os::raw::c_int;
}

pub mod mode {
    #[cfg(target_os = "windows")]
    pub const _O_TEXT: i32 = 0x4000;

    #[cfg(target_os = "windows")]
    pub const _O_BINARY: i32 = 0x8000;

    #[cfg(target_os = "windows")]
    pub const _O_WTEXT: i32 = 0x10000;

    #[cfg(target_os = "windows")]
    pub const _O_U16TEXT: i32 = 0x20000;

    #[cfg(target_os = "windows")]
    pub const _O_U8TEXT: i32 = 0x40000;
}

#[cfg(target_os = "windows")]
pub fn set_fd_mode(fd: i32, mode: i32) -> Result<i32, String> {
    use std::os::raw::c_int;

    let ret = unsafe { _setmode(c_int::from(fd), c_int::from(mode)) } as i32;
    if ret < 0 {
        let mut errno = c_int::default();
        let ret = unsafe { _get_errno(std::ptr::addr_of_mut!(errno)) };

        assert_eq!(ret, 0, "_get_errno() failed, errno: {ret}");
        assert_ne!(errno, 0);

        Err(format!("_setmode() failed, errno: {errno}"))
    } else {
        Ok(ret)
    }
}
