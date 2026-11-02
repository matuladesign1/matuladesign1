#!/usr/bin/env python3
"""Complète le dossier android/ généré par `flutter create` :
nom de l'application, Android 7.0 minimum, permissions, service audio
d'arrière-plan (notification), lecture vocale, signature release.

Usage : python3 tools/patch_android.py   (à lancer à la racine du projet)
Idempotent : peut être relancé sans risque.
"""
import glob
import os
import re
import sys

APP_LABEL = "Sermons de Branham Matomate"
ROOT = os.path.join("android", "app")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def patch_manifest():
    p = os.path.join(ROOT, "src", "main", "AndroidManifest.xml")
    s = read(p)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', s, count=1)
    perms = [
        "android.permission.INTERNET",
        "android.permission.WAKE_LOCK",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
        "android.permission.POST_NOTIFICATIONS",
    ]
    block = ""
    for perm in perms:
        if perm not in s:
            block += f'    <uses-permission android:name="{perm}"/>\n'
    if "READ_EXTERNAL_STORAGE" not in s:
        block += ('    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" '
                  'android:maxSdkVersion="32"/>\n')
    if block:
        s = re.sub(r"(<manifest[^>]*>\n)", r"\1" + block.replace("\\", "\\\\"), s, count=1)
    if "com.ryanheise.audioservice.AudioService" not in s:
        services = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
'''
        s = s.replace("</application>", services + "    </application>", 1)
    if "TTS_SERVICE" not in s:
        tts = '''        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
'''
        if "<queries>" in s:
            s = s.replace("<queries>\n", "<queries>\n" + tts, 1)
        else:
            s = s.replace("</manifest>", "    <queries>\n" + tts + "    </queries>\n</manifest>", 1)
    write(p, s)
    print("AndroidManifest.xml : OK")


def patch_activity():
    files = glob.glob(os.path.join(ROOT, "src", "main", "kotlin", "**", "MainActivity.kt"), recursive=True)
    if not files:
        sys.exit("MainActivity.kt introuvable")
    for p in files:
        s = read(p)
        if "AudioServiceActivity" not in s:
            s = s.replace("import io.flutter.embedding.android.FlutterActivity",
                          "import com.ryanheise.audioservice.AudioServiceActivity")
            s = s.replace(": FlutterActivity()", ": AudioServiceActivity()")
            write(p, s)
        print(f"{os.path.basename(p)} : OK")


SIGNING_GROOVY = '''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
'''

SIGNING_CONFIG_GROOVY = '''
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
                storeFile = file(keystoreProperties["storeFile"])
                storePassword = keystoreProperties["storePassword"]
            }
        }
    }
'''

SIGNING_KTS = '''
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}
'''

SIGNING_CONFIG_KTS = '''
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
'''


def patch_gradle():
    kts = os.path.join(ROOT, "build.gradle.kts")
    groovy = os.path.join(ROOT, "build.gradle")
    p = kts if os.path.exists(kts) else groovy
    s = read(p)
    s = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 24", s)
    if "keystorePropertiesFile" not in s:
        if p == kts:
            s = s.replace("\nandroid {", SIGNING_KTS + "\nandroid {", 1)
            s = s.replace("\nandroid {\n", "\nandroid {\n" + SIGNING_CONFIG_KTS, 1)
            s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
                          'else signingConfigs.getByName("debug")')
        else:
            s = s.replace("\nandroid {", SIGNING_GROOVY + "\nandroid {", 1)
            s = s.replace("\nandroid {\n", "\nandroid {\n" + SIGNING_CONFIG_GROOVY, 1)
            s = s.replace("signingConfig = signingConfigs.debug",
                          "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug")
    write(p, s)
    if "minSdk = 24" not in s:
        print("ATTENTION : minSdk non modifié, vérifiez " + p)
    print(f"{os.path.basename(p)} : OK")


def patch_toolchain():
    """Kotlin 2.1 / AGP 8.7 / Gradle 8.10 : versions attendues par les extensions récentes."""
    for name in ("settings.gradle", "settings.gradle.kts"):
        p = os.path.join("android", name)
        if os.path.exists(p):
            s = read(p)
            s = re.sub(r'(id[ (]+"org\.jetbrains\.kotlin\.android"\)?\s+version\s+)"[^"]+"', r'\1"2.1.0"', s)
            s = re.sub(r'(id[ (]+"com\.android\.application"\)?\s+version\s+)"[^"]+"', r'\1"8.7.3"', s)
            write(p, s)
            print(f"{name} : OK")
    p = os.path.join("android", "gradle", "wrapper", "gradle-wrapper.properties")
    if os.path.exists(p):
        s = re.sub(r"gradle-[\d.]+-(all|bin)\.zip", r"gradle-8.10.2-\1.zip", read(p))
        write(p, s)
        print("gradle-wrapper.properties : OK")


if __name__ == "__main__":
    if not os.path.isdir(ROOT):
        sys.exit("Dossier android/ absent : lancez d'abord « flutter create --platforms=android . »")
    patch_manifest()
    patch_activity()
    patch_gradle()
    patch_toolchain()
