#!/usr/bin/env bash
# Adds the native "Start on boot" pieces to the generated Android project.
set -euo pipefail
K=android/app/src/main/kotlin/dk/livetvplayer/live_tv_player
mkdir -p "$K"
cp android-native/MainActivity.kt android-native/BootReceiver.kt "$K/"
M=android/app/src/main/AndroidManifest.xml
# No cloud backup or device-to-device transfer of app data (Android 12+)
mkdir -p android/app/src/main/res/xml
cp android-native/res/xml/data_extraction_rules.xml android/app/src/main/res/xml/
sed -i 's|<application|<application android:dataExtractionRules="@xml/data_extraction_rules"|' $M
sed -i 's|<application|<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>\n    <application|' $M
sed -i 's|</application>|    <receiver android:name=".BootReceiver" android:exported="true">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>\n    </application>|' $M
grep -c BootReceiver $M
