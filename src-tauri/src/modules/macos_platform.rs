//! macOS tunnel authorization and lifetime management. The GUI stays unprivileged.

use crate::modules::error::AppError;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::{Child, ChildStdin, Command};
use tokio::sync::Mutex;

static TUNNEL_CONTROL: Mutex<Option<ChildStdin>> = Mutex::const_new(None);

fn is_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

pub async fn has_authorization() -> bool {
    is_root()
        || Command::new("/usr/bin/sudo")
            .args(["-n", "-v"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await
            .is_ok_and(|status| status.success())
}

pub async fn ensure_authorized() -> Result<(), AppError> {
    if has_authorization().await {
        return Ok(());
    }
    // Retain the existing password-dialog flow. Never place a password in argv,
    // environment variables, logs or files. Close authentication stdin so an
    // incorrect password cannot hang while sudo waits for another attempt.
    let script = r#"display dialog "MCTier 需要管理员权限来创建 macOS 虚拟网卡。请输入登录密码以继续。" with title "MCTier 网络授权" default answer "" with hidden answer buttons {"取消", "继续"} default button "继续" cancel button "取消"
text returned of result"#;
    let prompt = Command::new("/usr/bin/osascript")
        .args(["-e", script])
        .kill_on_drop(true)
        .output()
        .await
        .map_err(|e| AppError::ProcessError(format!("打开 macOS 授权对话框失败: {}", e)))?;
    if !prompt.status.success() {
        return Err(AppError::ProcessError(
            "已取消 macOS 管理员授权".to_string(),
        ));
    }
    let password = String::from_utf8(prompt.stdout)
        .map_err(|_| AppError::ProcessError("macOS 管理员密码格式无效".to_string()))?;
    let password = password.trim_end_matches(&['\r', '\n'][..]);
    if password.is_empty() {
        return Err(AppError::ProcessError(
            "未输入 macOS 管理员密码".to_string(),
        ));
    }
    let mut auth = Command::new("/usr/bin/sudo")
        .args(["-S", "-p", "", "-v"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| AppError::ProcessError(format!("macOS 授权失败: {}", e)))?;
    if let Some(mut input) = auth.stdin.take() {
        input
            .write_all(format!("{}\n", password).as_bytes())
            .await
            .map_err(|e| AppError::ProcessError(format!("macOS 授权失败: {}", e)))?;
    }
    let output = auth
        .wait_with_output()
        .await
        .map_err(|e| AppError::ProcessError(format!("macOS 授权失败: {}", e)))?;
    if !output.status.success() {
        return Err(AppError::ProcessError(
            "macOS 管理员密码不正确或当前账户无管理员权限".to_string(),
        ));
    }
    Ok(())
}

pub async fn spawn_tunnel(cmd: Command) -> Result<Child, AppError> {
    let needs_elevation = !is_root() && !cmd.as_std().get_args().any(|arg| arg == "--no-tun");
    if needs_elevation {
        ensure_authorized().await?;
    }
    let program = cmd.as_std().get_program().to_os_string();
    let args: Vec<_> = cmd
        .as_std()
        .get_args()
        .map(|arg| arg.to_os_string())
        .collect();
    let current_dir = cmd.as_std().get_current_dir().map(PathBuf::from);
    let mut supervisor = if needs_elevation {
        let mut sudo = Command::new("/usr/bin/sudo");
        sudo.args(["-n", "--", "/bin/bash"]);
        sudo
    } else {
        Command::new("/bin/bash")
    };
    supervisor
        .args([
            "-c",
            include_str!("../../../scripts/macos-easytier-supervisor.sh"),
            "mctier-easytier-supervisor",
        ])
        .arg(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    if let Some(dir) = current_dir {
        supervisor.current_dir(dir);
    }
    let mut child = supervisor
        .spawn()
        .map_err(|e| AppError::ProcessError(format!("启动 macOS EasyTier 失败: {}", e)))?;
    *TUNNEL_CONTROL.lock().await = child.stdin.take();
    Ok(child)
}

/// EOF stops only our supervised child, including after sudo's ticket expires.
/// The OS closes the same pipe if the GUI crashes.
pub async fn stop_tunnel() {
    TUNNEL_CONTROL.lock().await.take();
}
