// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::TrayIconBuilder;
use tauri::{Manager, RunEvent, WindowEvent};

struct OtpProcess(Mutex<Option<Child>>);

/// Resolve the OTP release directory.
///
/// In release builds, Tauri's `resource_dir()` points to where `bundle.resources`
/// placed files (passed dynamically via `--config`). The release lives at `rel/`
/// inside the resource directory — matching Livebook's convention.
///
/// In dev builds (`cargo build --release` without Tauri bundling), we fall back
/// to a manual search relative to the executable.
fn release_dir(app: &tauri::App) -> PathBuf {
    // 1. Environment override (always wins)
    if let Ok(dir) = std::env::var("WORTH_RELEASE_DIR") {
        let p = PathBuf::from(dir);
        if p.join("bin").exists() {
            return p;
        }
    }

    // 2. Tauri resource directory (release builds — AppImage, DMG, MSI, deb)
    if let Ok(resource_dir) = app.path().resource_dir() {
        let candidate = resource_dir.join("rel");
        if candidate.join("bin").exists() {
            return candidate;
        }
    }

    // 3. Dev build fallback: exe is at target/release/worth-desktop,
    //    release is at src-tauri/release
    let exe = std::env::current_exe().expect("cannot locate own executable");
    let base = exe.parent().expect("executable has no parent dir");
    let candidate = base.join("../../release");
    if candidate.join("bin").exists() {
        return candidate
            .canonicalize()
            .unwrap_or_else(|_| candidate.to_path_buf());
    }

    panic!(
        "Could not locate OTP release. Checked resource_dir/rel and dev paths relative to {:?}",
        base
    );
}

fn start_otp(release: &PathBuf) -> Child {
    let bin = if cfg!(target_os = "windows") {
        release.join("bin").join("desktop.bat")
    } else {
        release.join("bin").join("desktop")
    };

    Command::new(&bin)
        .arg("start")
        .env("WORTH_DESKTOP", "1")
        .env("RELEASE_DISTRIBUTION", "none")
        .env("PHX_HOST", "127.0.0.1")
        .env("PORT", "4090")
        .spawn()
        .unwrap_or_else(|e| panic!("Failed to start OTP release at {:?}: {}", bin, e))
}

fn stop_otp(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn stop_otp_state(app: &tauri::AppHandle) {
    if let Some(state) = app.try_state::<OtpProcess>() {
        if let Ok(mut guard) = state.0.lock() {
            if let Some(ref mut child) = *guard {
                stop_otp(child);
            }
        }
    }
}

fn main() {
    // WebKit2GTK 2.42+ inside an AppImage with linuxdeploy-plugin-gtk's bundled
    // libraries fails to initialise its DMA-BUF renderer against the host EGL
    // driver ("Could not create default EGL display: EGL_BAD_PARAMETER"),
    // leaving the webview blank. Forcing the legacy renderer avoids the EGL
    // path. Only do this when actually running from an AppImage so direct
    // binary runs keep hardware acceleration.
    #[cfg(target_os = "linux")]
    if std::env::var_os("APPIMAGE").is_some() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let release = release_dir(app);
            let child = start_otp(&release);
            app.manage(OtpProcess(Mutex::new(Some(child))));

            // Build tray menu
            let show = MenuItemBuilder::with_id("show", "Show Worth").build(app)?;
            let quit = MenuItemBuilder::with_id("quit", "Quit").build(app)?;
            let menu = MenuBuilder::new(app)
                .item(&show)
                .separator()
                .item(&quit)
                .build()?;

            // Create tray icon with the app icon
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Worth")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => {
                        stop_otp_state(app);
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::Click { .. } = event {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            // The splash screen (dist/index.html) polls until Phoenix is ready,
            // then navigates to http://127.0.0.1:4090 automatically.

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| match event {
            RunEvent::WindowEvent {
                label,
                event: WindowEvent::CloseRequested { .. },
                ..
            } if label == "main" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
                stop_otp_state(app);
                app.exit(0);
            }
            RunEvent::ExitRequested { .. } => {
                stop_otp_state(app);
            }
            _ => {}
        });
}
