#!/usr/bin/env bash
# Drives the Google TV app with remote-control key presses on an emulator and
# saves a screenshot after every step (run by .github/workflows/tv-ui-test.yml).
set -u
PKG=dk.livetvplayer.live_tv_player
OUT=shots
mkdir -p "$OUT"
n=0

shot() { n=$((n+1)); f=$(printf "%s/%s.png" "$OUT" "$1"); adb exec-out screencap -p > "$f"; echo "shot $f"; }
key()  { adb shell input keyevent "$1"; sleep "${2:-2}"; }
keys() { local k=$1 c=$2; for _ in $(seq "$c"); do adb shell input keyevent "$k"; sleep 0.9; done; sleep 1.5; }

adb wait-for-device
# Look like a 1080p Google TV: 1920x1080 at xhdpi (= 960x540 dp)
adb shell wm size 1920x1080
adb shell wm density 320
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

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

adb logcat -d > "$OUT/logcat_full.txt" || true
grep -E "flutter|AndroidRuntime|FATAL|mpv|media_kit" "$OUT/logcat_full.txt" | tail -400 > "$OUT/logcat_app.txt" || true
echo "done: $n screenshots"
