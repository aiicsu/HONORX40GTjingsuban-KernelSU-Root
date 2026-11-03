@echo off
chcp 936 >nul
setlocal enabledelayedexpansion
title 算本 boot 的内核基址（APK 用）
set "ROOT=%~dp0"
set "ADB=%ROOT%..\platform-tools\adb.exe"
if not exist "%ADB%" set "ADB=adb"

rem ============================================================
rem  作用：用 shell 身份测 perf 采样，反解 KASLR slide，把结果按 boot_id
rem        写到手机 /sdcard/Download/ghostlock-retry/base.txt。
rem
rem  什么时候需要：APK 没接 Shizuku 时。应用域 perf_event_open 被 SELinux
rem        拒（errno=13），自己测不出来，只能由主机代测。
rem
rem  每次手机重启都要重跑一次 —— slide 每个 boot 都变，用旧的值会写歪地址。
rem  应用自己会校验 boot_id，对不上会拒绝执行（这是故意的）。
rem ============================================================

echo === 计算本 boot 的内核基址 ===
echo.

python --version >nul 2>&1 || (
  echo [x] 需要 python（3.8+）在 PATH 里。
  echo     不想装 python 也可以：手机端装 Shizuku，用 APK 里的
  echo     「用 Shizuku 借 shell 身份测基址」，效果一样。
  goto :end
)

for /l %%i in (1,1,30) do (
  "%ADB%" shell getprop sys.boot_completed 2>nul | findstr /c:"1" >nul && goto :bootok
  ping -n 3 127.0.0.1 >nul
)
echo [x] 设备没就绪。
goto :end

:bootok
for /f "usebackq delims=" %%b in (`"%ADB%" shell cat /proc/sys/kernel/random/boot_id 2^>nul`) do set "BID=%%b"
echo [*] boot_id = %BID%

"%ADB%" push "%ROOT%perf_slide" /data/local/tmp/perf_slide >nul || (echo [x] push 失败 & goto :end)
"%ADB%" shell chmod 755 /data/local/tmp/perf_slide >nul 2>&1

echo [1/2] 采样中（约 10 秒）
"%ADB%" shell "/data/local/tmp/perf_slide 5 raw" > "%TEMP%\gl_ips.txt" 2>nul

echo [2/2] 反解 slide
python "%ROOT%solve_slide.py" "%TEMP%\gl_ips.txt" > "%TEMP%\gl_solve.txt" 2>&1
type "%TEMP%\gl_solve.txt"

set "BASE="
for /f "tokens=2 delims==" %%v in ('findstr /b "BEST_BASE=" "%TEMP%\gl_solve.txt"') do set "BASE=%%v"
if not defined BASE (
  echo.
  echo [x] 没解出来。可能采样太少：解锁手机后保持屏幕亮着，再跑一次。
  goto :end
)

"%ADB%" shell "mkdir -p /sdcard/Download/ghostlock-retry" >nul 2>&1
"%ADB%" shell "printf 'boot %BID%\ntext %BASE%\n' > /sdcard/Download/ghostlock-retry/base.txt"
echo.
echo [+] 已写入 base.txt：
"%ADB%" shell "cat /sdcard/Download/ghostlock-retry/base.txt"
echo.
echo     现在可以在手机上打开 GhostLock Retry 点「执行」了。
echo     注意：手机再次重启后必须重跑本脚本。

:end
echo.
if not "%GL_NOPAUSE%"=="1" pause
exit /b 0
