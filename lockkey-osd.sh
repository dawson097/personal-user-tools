#!/usr/bin/env bash
# ==============================================================================
# 本脚本通过Gemini AI 编写，因为本人对于sh脚本不甚擅长
# ==============================================================================

# ==============================================================================
# 语言环境自动检测与文本定义
# ==============================================================================
# 默认英文文本
CAPS_ON="Caps Lock: ON"
CAPS_OFF="Caps Lock: OFF"
NUM_ON="Num Lock: ON"
NUM_OFF="Num Lock: OFF"

# 根据当前系统的 LANG 变量切换文本
if [[ "$LANG" =~ "zh_CN" ]]; then
    # 简体中文环境
    CAPS_ON="大写锁定：开"
    CAPS_OFF="大写锁定：关"
    NUM_ON="数字键盘：开"
    NUM_OFF="数字键盘：关"
elif [[ "$LANG" =~ "zh_" ]]; then
    # 其他中文环境（如 zh_TW, zh_HK 繁体）
    CAPS_ON="大寫鎖定：開"
    CAPS_OFF="大寫鎖定：關"
    NUM_ON="數字鍵盤：開"
    NUM_OFF="數字鍵盤：關"
fi

# ==============================================================================
# 指定 Plasma 6 OSD 目标总线
# ==============================================================================
DBUS_BUS="org.freedesktop.Notifications"
DBUS_PATH="/org/kde/osdService"
DBUS_METHOD="org.kde.osdService.showText"

trigger_osd() {
    local icon="$1"
    local message="$2"
    qdbus6 "$DBUS_BUS" "$DBUS_PATH" "$DBUS_METHOD" "$icon" "$message" >/dev/null 2>&1
}

# ==============================================================================
# 硬件状态读取函数
# ==============================================================================
get_caps_status() {
    if ls /sys/class/leds/*capslock/brightness >/dev/null 2>&1; then
        cat /sys/class/leds/*capslock/brightness 2>/dev/null | grep -E '^[01]$' | head -n 1
    else
        echo "0"
    fi
}

get_num_status() {
    if ls /sys/class/leds/*numlock/brightness >/dev/null 2>&1; then
        cat /sys/class/leds/*numlock/brightness 2>/dev/null | grep -E '^[01]$' | head -n 1
    else
        echo "0"
    fi
}

# ==============================================================================
# 初始化基准状态
# ==============================================================================
last_caps=$(get_caps_status)
last_num=$(get_num_status)
[[ -z "$last_caps" ]] && last_caps="0"
[[ -z "$last_num" ]] && last_num="0"

# ==============================================================================
# 高效轮询
# ==============================================================================
while true; do
    current_caps=$(get_caps_status)
    current_num=$(get_num_status)

    [[ -z "$current_caps" ]] && current_caps=$last_caps
    [[ -z "$current_num" ]] && current_num=$last_num

    # 监控 Caps Lock
    if [ "$current_caps" != "$last_caps" ]; then
        if [ "$current_caps" = "1" ]; then
            trigger_osd "input-keyboard" "$CAPS_ON"
        else
            trigger_osd "input-keyboard" "$CAPS_OFF"
        fi
        last_caps="$current_caps"
    fi

    # 监控 Num Lock
    if [ "$current_num" != "$last_num" ]; then
        if [ "$current_num" = "1" ]; then
            trigger_osd "input-dialpad" "$NUM_ON"
        else
            trigger_osd "input-dialpad" "$NUM_OFF"
        fi
        last_num="$current_num"
    fi

    sleep 0.08
done
