@echo off
chcp 936 >nul
setlocal
title 安装 GhostLock Retry (APK)
set "ROOT=%~dp0"
set "ADB=%ROOT%..\platform-tools\adb.exe"
if not exist "%ADB%" set "ADB=adb"

echo === 安装 %ROOT%ghostlock-retry.apk ===
echo.

rem HONOR 默认会拦 adb 静默安装，先关掉确认弹窗（需要系统允许改这个 secure 项）
"%ADB%" shell settings put secure adb_install_need_confirm 0 >nul 2>&1
"%ADB%" shell settings put secure install_non_market_apps 1 >nul 2>&1

"%ADB%" install -r -g "%ROOT%ghostlock-retry.apk"
if errorlevel 1 (
  echo.
  echo [x] 安装失败。常见原因：
  echo     1. 手机上没点「允许安装」——看手机屏幕
  echo     2. 被手机管家拦了 —— 设置 ^> 安全 ^> 更多安全设置 ^> 外部来源应用
  echo     3. 数据线只能充电 —— 换成「传输文件」模式
  goto :end
)

rem 装完补一次存储权限（pm clear 会撤销掉，开机自启写日志要用）
"%ADB%" shell pm grant com.ghostlock.retry android.permission.READ_EXTERNAL_STORAGE >nul 2>&1
"%ADB%" shell pm grant com.ghostlock.retry android.permission.WRITE_EXTERNAL_STORAGE >nul 2>&1

echo.
echo [+] 装好了。手机上打开「GhostLock Retry」：
echo     1) 勾上「用 Shizuku 借 shell 身份测基址」（先启动 Shizuku）
echo        —— 或者先在电脑上双击 slide\算基址.cmd
echo     2) 点「执行」，弹授权框点「始终允许」
echo     3) 等 30 秒左右，看到 child is root! 就成了

:end
echo.
if not "%GL_NOPAUSE%"=="1" pause
exit /b 0
