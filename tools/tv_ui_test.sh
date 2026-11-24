#!/usr/bin/env bash
# Drives the Google TV app with remote-control key presses on an emulator and
# saves a screenshot after every step (run by .github/workflows/tv-ui-test.yml).
set -u
PKG=dk.livetvplayer.live_tv_player
OUT=shots
mkdir -p "$OUT"
n=0

shot() { n=$((n+1)); f=$(printf "%s/%02d_%s.png" "$OUT" "$n" "$1"); adb exec-out screencap -p > "$f"; echo "shot $f"; }
key()  { adb shell input keyevent "$1"; sleep "${2:-1.2}"; }
keys() { local k=$1 c=$2; for _ in $(seq "$c"); do adb shell input keyevent "$k"; sleep 0.5; done; sleep 1; }

adb wait-for-device
# Look like a 1080p Google TV: 1920x1080 at xhdpi (= 960x540 dp)
adb shell wm size 1920x1080
adb shell wm density 320
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

adb install -r -g app.apk
adb logcat -c
adb shell am start -n "$PKG/.MainActivity"
sleep 20
shot start_playing

key KEYCODE_DPAD_CENTER 2;      shot info_panel
key KEYCODE_DPAD_RIGHT;         shot info_tile_right
key KEYCODE_DPAD_DOWN 3;        shot zap_down
key KEYCODE_BACK;               shot info_closed
key KEYCODE_BACK 3;             shot guide
keys KEYCODE_DPAD_DOWN 4;       shot guide_down4
keys KEYCODE_DPAD_RIGHT 3;      shot guide_right3
keys KEYCODE_DPAD_LEFT 3;       shot guide_left3
adb shell input keyevent --longpress KEYCODE_DPAD_CENTER; sleep 1.5; shot guide_longpress_fav
key KEYCODE_DPAD_CENTER 4;      shot guide_ok_preview
key KEYCODE_BACK 2;             shot sidebar
keys KEYCODE_DPAD_DOWN 3;       shot sidebar_down3
key KEYCODE_DPAD_CENTER 3;      shot guide_category
key KEYCODE_DPAD_CENTER 4;      shot guide_ok_preview2
key KEYCODE_DPAD_CENTER 3;      shot fullscreen_info
keys KEYCODE_DPAD_UP 2;         shot zap_up2
key KEYCODE_BACK;               shot back_to_play
key KEYCODE_BACK 3;             shot guide_again
key KEYCODE_BACK 2;             shot sidebar_again
key KEYCODE_DPAD_LEFT;          shot sidebar_rail
key KEYCODE_DPAD_CENTER 3;      shot settings
keys KEYCODE_DPAD_DOWN 3;       shot settings_focus_down3
key KEYCODE_BACK 3;             shot back_from_settings

adb logcat -d > "$OUT/logcat_full.txt" || true
grep -E "flutter|AndroidRuntime|FATAL|mpv|media_kit" "$OUT/logcat_full.txt" | tail -400 > "$OUT/logcat_app.txt" || true
echo "done: $n screenshots"
