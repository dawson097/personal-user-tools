#!/usr/bin/env bash
# ==============================================================================
# 本脚本通过 GeminiAI 编写，基于Deepseek优化，因为本人对于 sh 脚本不甚擅长
# 功能：监控 Caps Lock / Num Lock 状态，通过 Plasma 6 OSD 实时显示
# 方案：优化轮询模式（~1% CPU），配合 flock 文件锁防止重复启动
# 延迟：~30ms（sleep 0.03，较旧版 80ms 降低 62%）
# ==============================================================================

# ==============================================================================
# 单实例锁 —— 防止重复启动撑爆 CPU
#
# 原理：
#   1. exec 200> 打开（或创建）锁文件，文件描述符 200 指向它
#   2. flock -n 尝试加锁（非阻塞），失败则说明已有实例在跑，直接退出
#   3. echo $$ 写入当前 PID 便于排查
#   4. 脚本退出时，FD 200 自动关闭 → 内核自动释放锁 → 无需 trap
#
# 注意：
#   - 不要加 trap 'rm -f "$LOCKFILE"' EXIT！
#     删文件不会释放锁（FD 还在），反而让新进程以为可加锁
# ==============================================================================
LOCKFILE="/tmp/lock-osd.lock"
LOCKFD=200
exec 200>"$LOCKFILE"
flock -n "$LOCKFD" || {
  echo "另一实例已在运行，退出 (PID: $(cat "$LOCKFILE" 2>/dev/null))"
  exit 1
}
echo $$ >"$LOCKFILE"

# ==============================================================================
# 语言环境自动检测与文本定义
# ==============================================================================
CAPS_ON="Caps Lock: ON"
CAPS_OFF="Caps Lock: OFF"
NUM_ON="Num Lock: ON"
NUM_OFF="Num Lock: OFF"

if [[ "$LANG" =~ "zh_CN" ]]; then
  CAPS_ON="大写锁定：开"
  CAPS_OFF="大写锁定：关"
  NUM_ON="数字键盘：开"
  NUM_OFF="数字键盘：关"
elif [[ "$LANG" =~ "zh_" ]]; then
  CAPS_ON="大寫鎖定：開"
  CAPS_OFF="大寫鎖定：關"
  NUM_ON="數字鍵盤：開"
  NUM_OFF="數字鍵盤：關"
fi

# ==============================================================================
# OSD 显示函数
# ==============================================================================
trigger_osd() {
  qdbus-qt6 \
    "org.freedesktop.Notifications" \
    "/org/kde/osdService" \
    "org.kde.osdService.showText" "$1" "$2" >/dev/null 2>&1
}

# ==============================================================================
# 优化①：启动时缓存设备路径，避免每次循环都做 glob 展开
# ==============================================================================
CAPS_PATH=$(ls /sys/class/leds/*capslock/brightness 2>/dev/null | head -1)
NUM_PATH=$(ls /sys/class/leds/*numlock/brightness 2>/dev/null | head -1)

# ==============================================================================
# 优化②：用 bash 内置 read 替代 cat，减少外部进程创建
# ==============================================================================
get_caps_status() {
  local val
  [ -n "$CAPS_PATH" ] && read -r val <"$CAPS_PATH" || val=0
  echo "${val:-0}"
}
get_num_status() {
  local val
  [ -n "$NUM_PATH" ] && read -r val <"$NUM_PATH" || val=0
  echo "${val:-0}"
}

# ==============================================================================
# 初始化基准状态
# ==============================================================================
last_caps=$(get_caps_status)
last_num=$(get_num_status)
[[ -z "$last_caps" ]] && last_caps="0"
[[ -z "$last_num" ]] && last_num="0"

# ==============================================================================
# 优化③：主循环 —— sleep 0.03（30ms），延迟降低 62%
# 旧版 sleep 0.08（80ms），按键按下到 OSD 显示最长等 80ms
# 新版 sleep 0.03（30ms），按键按下到 OSD 显示最长等 30ms
# CPU 占用约 1%，体感几乎不可察觉
# ==============================================================================
while true; do
  current_caps=$(get_caps_status)
  current_num=$(get_num_status)
  [[ -z "$current_caps" ]] && current_caps=$last_caps
  [[ -z "$current_num" ]] && current_num=$last_num

  # ---- Caps Lock 变化 ----
  if [ "$current_caps" != "$last_caps" ]; then
    [ "$current_caps" = "1" ] && trigger_osd "input-keyboard" "$CAPS_ON" ||
      trigger_osd "input-keyboard" "$CAPS_OFF"
    last_caps="$current_caps"
  fi

  # ---- Num Lock 变化 ----
  if [ "$current_num" != "$last_num" ]; then
    [ "$current_num" = "1" ] && trigger_osd "input-dialpad" "$NUM_ON" ||
      trigger_osd "input-dialpad" "$NUM_OFF"
    last_num="$current_num"
  fi

  sleep 0.03
done
