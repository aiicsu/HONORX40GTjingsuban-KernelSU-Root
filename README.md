# GhostLock 便携包

GhostLock 便携包 —— 使用说明
================================================

适用设备（硬限制，先看这条）
------------------------------------------------
  型号代码  ADT-AN00（ro.product.device = HNADT-Q）
  市场名称  荣耀 X40 GT 竞速版
  内核      5.4.289-qgki-gf6cb1f712a6e
  系统      Android 14 / MagicOS 8.0.0.220

所有内核偏移、符号地址都是按这套内核算出来的。换别的型号或别的内核版本，
W1 会往错误的内核地址写东西，手机会当场重启，严重时会起不来。
一键脚本里有校验，机型/内核对不上会直接拒绝（确认要试可以设 GL_FORCE=1）。


包里有什么
------------------------------------------------
  一键提权.cmd          电脑端入口，双击就跑完整条链
  bin\glbin             内核利用二进制（设备端执行）
  bin\payload_run.bin   它的输入 profile
  bin\glpc.sh           设备端分阶段执行器
  apk\ghostlock-retry.apk      手机端 App（5.2 MB，自带 KernelSU 组件，见路线 B）
  apk\装APK.cmd         用 adb 装这个 App
  slide\算基址.cmd    给 App 算本 boot 的内核基址（路线 B 用）
  slide\perf_slide     采样器
  slide\solve_slide.py 反解 KASLR slide
  slide\symbols.txt    符号表（打分用，删掉也能跑）
  platform-tools\       自带 adb，不用另外装


路线 A：电脑一键（推荐，最省事）
------------------------------------------------
  1. 手机：设置 -> 关于手机 -> 连点版本号 7 次，开开发者选项
           开发者选项里打开「USB 调试」
  2. USB 连电脑，手机上弹出「允许 USB 调试吗」-> 勾「一律允许」-> 允许
  3. 双击 一键提权.cmd

  脚本会自己做完：
      推送工具链 -> W1 关 SELinux -> W2/W3 写 cred、晚加载 KernelSU
      -> 切回 Enforcing -> 验证 su / 内核模块 / root 写盘 / 截图

  手机上不用点任何东西。全程约 1-2 分钟。

  如果中途手机重启了（W2 那一步约有 40-60% 概率触发内核静默复位，
  这是 PI 竞态的固有问题，不是包坏了），脚本会等你开机后自动重来，
  最多 3 轮。真的 3 轮都没成，就再双击一次。

  成功后验证：
      adb shell su -c id
      => uid=0(root) ... context=u:r:ksu:s0


路线 B：手机 App（不用电脑，但要先给一次内核基址）
------------------------------------------------
  App 跑在应用域，SELinux 不让应用调 perf_event_open（errno=13），
  所以它自己测不出 KASLR slide，必须从外面拿一次基址。两种给法：

  B-1 借 Shizuku（手机端全搞定）
      1. 手机装 Shizuku（应用商店/官网），打开后选「通过连接电脑启动」，
         按它提示在电脑上执行一条 adb 命令（一次性）
      2. 双击 apk\装APK.cmd 装 App
      3. 打开 App，勾上「用 Shizuku 借 shell 身份测基址」，点「执行」
      4. 弹授权框点「始终允许」，等 30 秒左右
      日志里出现 child is root! + KernelSU ready 就成了

  B-2 电脑给基址（没装 Shizuku 时）
      1. 双击 slide\算基址.cmd（需要电脑有 python 3.8+）
         它会把结果按 boot_id 写进手机 /sdcard/Download/ghostlock-retry/base.txt
      2. 打开 App，不用勾 Shizuku，直接点「执行」

  APK 里自带 KernelSU 要用的四样东西（kernelsu.ko / ksud / magiskpolicy /
  ksu_rules，一共 9 MB，所以装完是 5.2 MB）。App 启动时把它们解到自己的
  私有目录，root 脚本再搬到 /data/local/tmp/ksu_fne —— **换一台手机不用再
  手工推任何文件**。以前这四样只在开发机上，别的机器上跑就会出现「W1/W2/W3
  全成功、child is root 也打出来了，但没有 su」，日志最后一行是
  `module load pending`。

  注意：手机每重启一次，slide 就变一次。B-2 每次开机都要重跑算基址.cmd。
        App 自己会校验 boot_id，发现基址是上一次开机的会拒绝执行
        （这是故意设计的——用旧基址会写歪地址，把手机送走）。

  App 的行为：
      - 一次点击最多连打 8 把（W1 单把命中率约 50%，打空无副作用）
      - W1 打上后自动分两段：第一段只关 SELinux 就退出，第二段用新进程做 W2
        （同进程连着做会撞 W1 留下的幽灵 waiter，那是之前复位的真正原因）
      - 跑完自动把 SELinux 切回 Enforcing，见下一节


关于 SELinux：为什么过程中是「宽容模式」，跑完会不会一直这样
------------------------------------------------
  W1 必须把 selinux_state.enforcing 写成 0 —— 这是漏洞利用的前提，
  要写内核内存，先得让 SELinux 不拦你的进程。所以提权过程中整机是
  Permissive，KernelSU 管理器首页会显示「宽容模式」。

  KernelSU 加载之后就不需要这样了：root 由模块在策略内提供
  （su 的域是 u:r:ksu:s0），再开着 Permissive 等于把整机防护白送。

  这个包会自己收回来：root 阶段的脚本在 ksud insmod 成功、
  四个 ksud 阶段跑完之后，执行

      echo 1 > /sys/fs/selinux/enforce

  收尾必须在那个脚本里做，不能在 App 里做 —— KernelSU 是**晚加载**的
  （系统跑起来之后才 insmod），它的挂载只进 init 的 mount namespace；
  而 App 的 namespace 是 zygote 更早 fork 出来的，之后 init 那边的挂载
  不会传播过来。实测 App 里 /system/bin/su、/data/adb/ksu/bin/su 全是
  ENOENT，/proc/self/mountinfo 里一条 ksu 挂载都没有。能看见 su 的只有
  本来就在 init namespace 的身份：adb shell 和 Shizuku。

  验证过（冷启动、Enforcing、无 root，点一次执行）：

      32 秒拿到 root  ->  getenforce 自动回到 Enforcing
      su -c id        ->  uid=0(root) context=u:r:ksu:s0
      screencap       ->  正常（说明 selinux_state.initialized 没被打掉）
      KernelSU 首页   ->  SELinux 状态：强制执行

  如果哪天又看到「宽容模式」：
      adb shell getenforce
      adb shell su -c 'echo 1 > /sys/fs/selinux/enforce'
    root 已经在手上，这条命令是幂等的。如果 KernelSU 根本没加载，
    收尾会故意跳过（不能既没 root 又把机器锁上）。


出问题了怎么查（不用 root，直接把文件拷出来看）
------------------------------------------------
  跑完之后手机上有三个文件，按这个顺序看：

  1. /sdcard/Download/ghostlock-retry/status.txt
         root 脚本写的结论，就三行，例：
             ksu=1
             enforce=0
         ksu=1 表示 KernelSU 模块真加载了；enforce=0 是写这张纸的时候
         SELinux 还是宽容模式（收尾在那之后才做，这是正常的）。
         这个文件不存在 = root 脚本根本没跑到那一步，看第 3 个文件。

  2. /sdcard/Download/ghostlock-retry/run-<时间>.log
         exploit 自己的输出。关键几行：
             [+] child is root!        W2 成功，临时 root 到手
             [+] KernelSU ready        KSU 在 3 秒内起来了（运气好才有）
             === exit 0 ksu=... ===    ksu 只有上面那行出现才是 true
         如果只有 child is root 没有 KernelSU ready，不要急着当失败 ——
         ksud 一般要 10-30 秒，exploit 只等 3 秒。以 status.txt 为准。

  3. App 私有目录里的 .ghostlock_ksu.log（要 root 才能看）
         adb shell su -c 'cat /data/user/0/com.ghostlock.retry/files/.ghostlock_ksu.log'
         里面有 step: 标记，能看出卡在哪一步：
             step: insmod-ok          → 模块加载成功
             step: ksud-stages-done   → 四个 ksud 阶段都过了
             step: harden-enter       → 开始切回 Enforcing
         如果看到 [!] .../kernelsu.ko missing，就是 APK 太旧（没有自带组件）。


常见问题
------------------------------------------------
  装 APK 报 INSTALL_FAILED_ABORTED
      荣耀拦了 adb 静默安装。装APK.cmd 已经帮你关了确认弹窗；还不行就看
      手机屏幕有没有「是否安装」的对话框，或去 手机管家 -> 应用启动管理。

  复位后 App 不会自己起来
      荣耀的 iaware 把 BOOT_COMPLETED 广播和持久化 JobScheduler 都拦了，
      代码侧绕不过去。要做的是：手机管家 -> 应用启动管理 -> 找到
      GhostLock Retry -> 关掉「自动管理」，手动打开「允许自启动」。
      不开也能用，就是每次复位后手动点一次执行。

  脚本说找不到 adb
      platform-tools 文件夹要和 一键提权.cmd 在同一层。整个文件夹一起拷。

  脚本说没检测到设备
      换数据线（有的线只能充电）；手机上确认 USB 调试授权弹窗点了允许；
      adb kill-server 后再试。

  跑完 App 说「kernelsu 未加载」但 adb 里 su 能用
      大概率是判定时机问题：exploit 只等 3 秒就退出，ksud 还没 insmod 完。
      现在的版本会去读 status.txt 再判一次，看到「已通知」字样就是真成功了。
      用 adb shell su -c id 复核最直接。

  跑完 su 能用但 App 里看不到 su
      KSU 的 su 挂在 /data/adb/ksu/bin/su，有些 App 的 mount namespace 里不可见。
      adb shell su -c id 能用就说明 root 是好的。


风险提示
------------------------------------------------
  这是内核漏洞利用（CVE-2026-43499 的 GhostLock 手法），本质是把内核内存
  写坏来达到提权，不是官方解锁。虽然本包里每一步都做过验证、失败路径是
  干净的，但仍存在：设备复位、数据未保存丢失、极低概率起不来（需要刷机恢复）。

  只在自己的设备上使用。
