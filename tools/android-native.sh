#!/usr/bin/env bash
# Adds the native "Start on boot" pieces to the generated Android project.
set -euo pipefail
K=android/app/src/main/kotlin/dk/livetvplayer/live_tv_player
mkdir -p "$K"
cp android-native/MainActivity.kt android-native/BootReceiver.kt android-native/ReminderReceiver.kt android-native/RefreshJob.kt "$K/"
M=android/app/src/main/AndroidManifest.xml
# No cloud backup or device-to-device transfer of app data (Android 12+)
mkdir -p android/app/src/main/res/xml
cp android-native/res/xml/data_extraction_rules.xml android/app/src/main/res/xml/
sed -i 's|<application|<application android:dataExtractionRules="@xml/data_extraction_rules"|' $M
sed -i 's|<application|<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>\n    <application|' $M
sed -i 's|</application>|    <receiver android:name=".BootReceiver" android:exported="true">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>\n        <receiver android:name=".ReminderReceiver" android:exported="false"/>\n        <service android:name=".RefreshJob" android:permission="android.permission.BIND_JOB_SERVICE" android:exported="false"/>\n    </application>|' $M
# "Open with LiveTV Player" for backup files in file managers
python3 - "$M" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
f = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:scheme="content" android:mimeType="application/json"/>
                <data android:scheme="file" android:mimeType="application/json"/>
            </intent-filter>'''
i = s.index('</intent-filter>') + len('</intent-filter>')
s = s[:i] + f + s[i:]
open(p, 'w').write(s)
PYEOF
# Android 11+ only lets the app see other apps it declares here: the voice
# recognizer, share targets and the file picker. Without this, voice search
# is reported as unavailable on Google TV and phones.
python3 - "$M" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
q = '''
        <intent><action android:name="android.speech.action.RECOGNIZE_SPEECH"/></intent>
        <intent><action android:name="android.speech.RecognitionService"/></intent>
        <intent><action android:name="android.intent.action.SEND"/><data android:mimeType="text/plain"/></intent>
        <intent><action android:name="android.intent.action.OPEN_DOCUMENT"/><data android:mimeType="*/*"/></intent>'''
if '<queries>' in s:
    s = s.replace('<queries>', '<queries>' + q, 1)
else:
    s = s.replace('</manifest>', '    <queries>' + q + '\n    </queries>\n</manifest>', 1)
open(p, 'w').write(s)
PYEOF
grep -c BootReceiver $M
