#!/bin/sh
# Xray LED Status Monitor
# Monitors Xray service health and updates router LED accordingly
#
# LED States:
#   White (system) = Xray running and healthy
#   Blue (run) = Xray starting or transitioning
#   Off = Xray stopped or failed

LED_BLUE="/sys/class/leds/blue:run"
LED_WHITE="/sys/class/leds/white:system"
CHECK_INTERVAL=10

# Set LED color/state
set_led_state() {
    local state="$1"

    case "$state" in
        healthy)
            # White LED on = healthy and running
            [ -d "$LED_WHITE" ] && {
                echo 255 > "$LED_WHITE/brightness"
                echo none > "$LED_WHITE/trigger"
            }
            [ -d "$LED_BLUE" ] && echo 0 > "$LED_BLUE/brightness"
            ;;
        starting)
            # Blue LED on = starting/transitioning
            [ -d "$LED_BLUE" ] && {
                echo 255 > "$LED_BLUE/brightness"
                echo none > "$LED_BLUE/trigger"
            }
            [ -d "$LED_WHITE" ] && echo 0 > "$LED_WHITE/brightness"
            ;;
        failed)
            # Blue LED blinking = failed/error
            [ -d "$LED_BLUE" ] && {
                echo timer > "$LED_BLUE/trigger"
                echo 250 > "$LED_BLUE/delay_on"
                echo 250 > "$LED_BLUE/delay_off"
            }
            [ -d "$LED_WHITE" ] && echo 0 > "$LED_WHITE/brightness"
            ;;
        stopped)
            # Both LEDs off = stopped
            [ -d "$LED_BLUE" ] && {
                echo 0 > "$LED_BLUE/brightness"
                echo none > "$LED_BLUE/trigger"
            }
            [ -d "$LED_WHITE" ] && echo 0 > "$LED_WHITE/brightness"
            ;;
    esac
}

# Check Xray health
check_xray_health() {
    # Check if xray process is running
    if ! pgrep -x xray > /dev/null 2>&1; then
        return 1
    fi

    # Check if nftables rules are loaded
    if ! nft list table ip xray > /dev/null 2>&1; then
        return 2
    fi

    # Check if routing rules exist
    if ! ip rule list | grep -q "fwmark 0x1 lookup 100"; then
        return 3
    fi

    return 0
}

# Main monitoring loop
last_state=""
startup_grace=0

while true; do
    # During first 30 seconds after boot, show starting state
    if [ -f /tmp/xray_startup_executed ] && [ $startup_grace -lt 3 ]; then
        startup_grace=$((startup_grace + 1))
        if [ "$last_state" != "starting" ]; then
            set_led_state starting
            last_state="starting"
        fi
        sleep $CHECK_INTERVAL
        continue
    fi

    check_xray_health
    health_status=$?

    case $health_status in
        0)
            # Healthy
            if [ "$last_state" != "healthy" ]; then
                set_led_state healthy
                last_state="healthy"
            fi
            ;;
        1)
            # Process not running - stopped
            if [ "$last_state" != "stopped" ]; then
                set_led_state stopped
                last_state="stopped"
            fi
            startup_grace=0
            ;;
        *)
            # Rules not loaded - failed
            if [ "$last_state" != "failed" ]; then
                set_led_state failed
                last_state="failed"
            fi
            startup_grace=0
            ;;
    esac

    sleep $CHECK_INTERVAL
done
