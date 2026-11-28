#!/usr/bin/env bash
# Drives the Google TV app with remote-control key presses on an emulator and
# saves a screenshot after every step (run by .github/workflows/ui-test-tv.yml).
set -u
PKG=dk.livetvplayer.live_tv_player
OUT=shots
mkdir -p "$OUT"
n=0

shot() { n=$((n+1)); f=$(printf "%s/%s.png" "$OUT" "$1"); adb exec-out screencap -p > "$f"; echo "shot $f"; }
key()  { adb shell input keyevent "$1"; sleep "${2:-2}"; }
keys() { local k=$1 c=$2; for _ in $(seq "$c"); do adb shell input keyevent "$k"; sleep 0.9; done; sleep 1.5; }

adb wait-for-device
# let the freshly booted emulator settle (boot-time background work starves
# apps of CPU and causes false "isn't responding" dialogs)
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
sleep 45
# Look like a 1080p Google TV: 1920x1080 at xhdpi (= 960x540 dp)
adb shell wm size 1920x1080
adb shell wm density 320
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
# no "Viewing full screen" tip over the screenshots
adb shell settings put secure immersive_mode_confirmations confirmed

adb install -r -g app.apk
adb logcat -c

# Each scenario starts from a fresh launch so one slow/missed key press on
# the (software-rendered) emulator cannot shift every later screenshot.
fresh() { adb shell am force-stop "$PKG"; sleep 1; adb shell am start -n "$PKG/.MainActivity" >/dev/null; sleep 14; }

# A: watching + info panel
fresh;                                  shot A1_watching
key KEYCODE_DPAD_CENTER 3;              shot A2_info_panel
key KEYCODE_DPAD_RIGHT 2;               shot A3_info_tile_right
key KEYCODE_DPAD_DOWN 4;                shot A4_zap_down
key KEYCODE_BACK 2;                     shot A5_info_closed

# B: guide navigation, favourite, preview, fullscreen
fresh
key KEYCODE_BACK 3;                     shot B1_guide
keys KEYCODE_DPAD_DOWN 4;               shot B2_guide_down4
keys KEYCODE_DPAD_RIGHT 3;              shot B3_guide_right3
keys KEYCODE_DPAD_LEFT 3;               shot B4_guide_left3
adb shell input keyevent --longpress KEYCODE_DPAD_CENTER; sleep 2; shot B5_guide_longpress_fav
key KEYCODE_DPAD_CENTER 5;              shot B6_guide_ok_preview
key KEYCODE_DPAD_CENTER 4;              shot B7_guide_ok_again_fullscreen

# C: sidebar + category
fresh
key KEYCODE_BACK 3; key KEYCODE_BACK 2; shot C1_sidebar
keys KEYCODE_DPAD_DOWN 3;               shot C2_sidebar_down3
key KEYCODE_DPAD_CENTER 3;              shot C3_guide_for_category
key KEYCODE_BACK 2;                     shot C4_sidebar_again
key KEYCODE_BACK 3;                     shot C5_back_to_watching

# D: settings via the sidebar rail
fresh
key KEYCODE_BACK 3; key KEYCODE_BACK 2
key KEYCODE_DPAD_LEFT 2;                shot D1_sidebar_rail
key KEYCODE_DPAD_CENTER 4;              shot D2_settings
keys KEYCODE_DPAD_DOWN 2;               shot D3_settings_down2
key KEYCODE_DPAD_CENTER 3;              shot D4_settings_open_item
key KEYCODE_BACK 2;                     shot D5_back
key KEYCODE_BACK 3;                     shot D6_back_to_tv

# E: leave with HOME and come back: the picture must keep moving
fresh
key KEYCODE_HOME 6
adb shell am start -n "$PKG/.MainActivity" >/dev/null; sleep 12
shot E1_resumed_a; sleep 3; shot E2_resumed_b

# G: Search from the sidebar: type in the Android text field, Enter
fresh
key KEYCODE_BACK 3; key KEYCODE_BACK 3          # guide, then sidebar
key KEYCODE_DPAD_UP 1; key KEYCODE_DPAD_UP 1; key KEYCODE_DPAD_UP 2   # to "Søg/Search"
shot G1_sidebar_search
key KEYCODE_DPAD_CENTER 4                       # opens the text field
shot G2_search_field
adb shell input text "Sport"; sleep 2
shot G3_typed
key KEYCODE_ENTER 5
shot G4_results

adb logcat -d > "$OUT/logcat_full.txt" || true
# Android's freeze ("not responding") reports with the blocking stack traces
adb root >/dev/null 2>&1 || true; sleep 3
for f in $(adb shell ls /data/anr 2>/dev/null | tr -d '\r'); do
  adb shell cat "/data/anr/$f" > "$OUT/anr_$f.txt" 2>/dev/null || true
done
grep -E "flutter|AndroidRuntime|FATAL|mpv|media_kit" "$OUT/logcat_full.txt" | tail -400 > "$OUT/logcat_app.txt" || true

# F: "Start on boot" – switch it on the way the app does (flag file +
# "display over other apps"), reboot, and check Live TV is in front.
UIDN=$(adb shell stat -c %u "/data/data/$PKG" | tr -d '\r')
adb shell "mkdir -p /data/data/$PKG/files && touch /data/data/$PKG/files/autostart_on_boot && chown $UIDN:$UIDN /data/data/$PKG/files/autostart_on_boot"
adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
adb shell am force-stop "$PKG"
adb reboot
sleep 20
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
sleep 60
adb shell wm size 1920x1080; adb shell wm density 320
sleep 5
shot F1_after_reboot
if adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | grep -q "$PKG"; then
  echo "BOOT_AUTOSTART=ok" | tee "$OUT/boot_autostart.txt"
else
  echo "BOOT_AUTOSTART=failed" | tee "$OUT/boot_autostart.txt"
  adb shell dumpsys activity activities | grep -E "ResumedActivity" >> "$OUT/boot_autostart.txt" || true
  adb logcat -d | grep -iE "BootReceiver|background activity|BAL|live_tv" | tail -50 >> "$OUT/boot_autostart.txt" || true
fi
echo "done: $n screenshots"
