# Build Ew Brother Ew on EC2

These are exact commands for **Ubuntu 22.04 or 24.04, x86_64**. Every version and checksum below was checked on 1 Nov 2026.

| Tool | Version |
| --- | --- |
| Flutter | 3.47.9 stable (Dart 3.13.7) |
| JDK | OpenJDK 17 (apt) |
| Android cmdline-tools | 16111833 (latest) |
| Android platform / build-tools / NDK | android-36 / 36.0.0 / 28.2.13676358 |
| AGP / Gradle / Kotlin | 9.1.0 / 9.3.1 (auto) / 2.4.0 |

The first build takes about 10 to 15 minutes. Later builds take 2 to 3 minutes.

---

## 0. Instance

- AMI: Ubuntu Server 24.04 LTS, **x86_64** (not ARM/Graviton)
- Type: **t3.large** (8 GB RAM) or bigger
- Disk: **30 GB** gp3
- Security group: SSH (22) from your IP only

Replace `EC2_IP` and `C:\path\to\key.pem` below with your own values.

## 1. Copy the project from your PC (PowerShell on Windows)

```powershell
scp -i C:\path\to\key.pem -r "C:\Users\Naveen\Desktop\Ew Brother Ew\ew_brother_ew" ubuntu@EC2_IP:~/
ssh -i C:\path\to\key.pem ubuntu@EC2_IP
```

Everything from here runs **on the EC2 machine**.

## 2. System packages (only installs what is missing, and remembers it for cleanup)

```bash
sudo apt-get update
for p in curl git unzip zip xz-utils openjdk-17-jdk-headless; do dpkg -s "$p" >/dev/null 2>&1 || echo "$p"; done > ~/ew-installed-pkgs.txt
cat ~/ew-installed-pkgs.txt
[ -s ~/ew-installed-pkgs.txt ] && sudo apt-get install -y $(cat ~/ew-installed-pkgs.txt)
java -version
```

`java -version` must say **17**.

Add 4 GB of swap so Gradle doesn't run out of memory on 8 GB:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
free -h
```

## 3. Flutter 3.47.9

```bash
cd ~
curl -fLO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz
echo "25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a  flutter_linux_3.47.9-stable.tar.xz" | sha256sum -c -
tar -xf flutter_linux_3.47.9-stable.tar.xz
rm flutter_linux_3.47.9-stable.tar.xz
```

`sha256sum` must print `OK`.

## 4. Android SDK

```bash
mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk/cmdline-tools
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
echo "e025545c62a8e64c7559119566a569fb1dec5f60  commandlinetools-linux-16111833_latest.zip" | sha1sum -c -
unzip -q commandlinetools-linux-16111833_latest.zip
mv cmdline-tools latest
rm commandlinetools-linux-16111833_latest.zip
```

## 5. Environment (one file, easy to delete later)

```bash
cat > ~/ew-env.sh <<'EOF'
export ANDROID_HOME=$HOME/android-sdk
export ANDROID_SDK_ROOT=$HOME/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$HOME/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
EOF
source ~/ew-env.sh
```

If you reconnect over SSH later, run `source ~/ew-env.sh` again.

## 6. SDK packages and licences

```bash
yes | sdkmanager --licenses > /dev/null
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"
flutter config --no-analytics
dart --disable-analytics
flutter config --android-sdk "$ANDROID_HOME"
yes | flutter doctor --android-licenses > /dev/null
flutter doctor -v
```

In `flutter doctor`, **Flutter** and **Android toolchain** must be ticked. Warnings about Chrome, Linux toolchain or Android Studio don't matter.

## 7. Release signing key (first time only)

This key signs every future update. **If you lose it, updates won't install over the old app and you'll have to uninstall, which loses your data unless you made a backup.**

```bash
mkdir -p ~/ew-keys
read -s -p "Choose a keystore password (6+ chars): " EWPASS; echo
keytool -genkeypair -keystore ~/ew-keys/ewbrother-release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias ewbrother \
  -storepass "$EWPASS" -keypass "$EWPASS" -dname "CN=Ew Brother Ew, O=Personal, C=IN"
cat > ~/ew_brother_ew/android/key.properties <<EOF
storePassword=$EWPASS
keyPassword=$EWPASS
keyAlias=ewbrother
storeFile=$HOME/ew-keys/ewbrother-release.jks
EOF
unset EWPASS
```

**Building again later on a NEW EC2 machine:** upload your saved `ewbrother-release.jks` into `~/ew-keys/`. Then run only the `read -s ...` line and the `cat > ... key.properties` block above, using the same password.

## 8. Build

```bash
cd ~/ew_brother_ew
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

- `flutter analyze` must report **no errors**. "info" lines are fine. If it shows errors, copy the output to me.
- `flutter test` must say **All tests passed**.

Check the APK:

```bash
$ANDROID_HOME/build-tools/36.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk | head -3
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

- The signer must show `CN=Ew Brother Ew`.
- The permission list must **not** contain `android.permission.INTERNET`.

## 9. Download to your PC (PowerShell on Windows)

```powershell
scp -i C:\path\to\key.pem ubuntu@EC2_IP:~/ew_brother_ew/build/app/outputs/flutter-apk/app-release.apk "$env:USERPROFILE\Desktop\EwBrotherEw.apk"
scp -i C:\path\to\key.pem ubuntu@EC2_IP:~/ew-keys/ewbrother-release.jks "$env:USERPROFILE\Desktop\ewbrother-release.jks"
```

Keep `ewbrother-release.jks` **and its password** somewhere safe, such as a password manager.

## 10. Uninstall everything the build installed (on EC2)

This removes Flutter, the Android SDK, JDK 17, Gradle/pub/Dart caches and the swap file. **It keeps `~/ew-keys/`** (your signing key). Run step 9 first.

```bash
cd ~
sudo swapoff /swapfile 2>/dev/null; sudo rm -f /swapfile
rm -rf ~/flutter ~/android-sdk ~/.gradle ~/.pub-cache ~/.android ~/.dart ~/.dart-tool ~/.dartServer \
       ~/.flutter ~/.flutter-devtools ~/.config/flutter ~/.config/dart ~/.kotlin ~/.m2 ~/.cache/flutter
rm -rf ~/ew_brother_ew/build ~/ew_brother_ew/.dart_tool ~/ew_brother_ew/android/.gradle ~/ew_brother_ew/android/.kotlin
[ -s ~/ew-installed-pkgs.txt ] && sudo apt-get purge -y $(cat ~/ew-installed-pkgs.txt)
sudo apt-get purge -y 'openjdk-17-*' 2>/dev/null
sudo apt-get autoremove -y --purge
sudo apt-get clean
rm -f ~/ew-env.sh ~/ew-installed-pkgs.txt
df -h ~
```

- The second `apt-get purge` removes JDK pieces pulled in as dependencies. Skip it if you had JDK 17 before step 2.
- `~/ew_brother_ew` (source code) and `~/ew-keys` stay. Delete them with `rm -rf ~/ew_brother_ew ~/ew-keys` only after downloading the key.
- If you're terminating the instance anyway, steps 9 and 10 are enough. Nothing else survives termination.

---

## 11. Install and set up on the phone (any Android 8+)

1. Copy `EwBrotherEw.apk` to the phone (USB, Quick Share, or Telegram Saved Messages) and open it. Allow "Install unknown apps" for that source. Play Protect or the phone may warn about an unknown app; tap through, or pause Play Protect scanning while installing.
2. Open **Ew Brother Ew** and tap **Finish setup** (or go to Settings, then Setup and permissions). Then:
   - **Accessibility service**: turn on "Ew Brother Ew reel counter". **If it's greyed out or says "Restricted setting"** (Android blocks this for sideloaded apps): go to App info, tap the three dots at the top right, choose **Allow restricted settings**, and try again.
   - **Usage access**: allow it.
   - **Notifications**: allow.
   - **Battery**: pick the unrestricted option (Xiaomi: No restrictions, most others: Unrestricted).
3. **Phone extras** (only shown on phones that need them): Autostart / Auto launch (Xiaomi, Oppo/Realme/OnePlus, Vivo, Huawei/Honor), Never sleeping apps (Samsung), pop-up windows in background (Xiaomi), and lock the app in recents. Stock Android phones need nothing extra.
4. Settings > **Preview the pause** shows the real pause screen.
5. Scroll 10 Reels. The bubble should count, and the pause should appear at 10.

**If counting doesn't work:** go to Settings > **Detection check** and scroll some reels. If the reel feed shows up grey there, tap **Count this**. No rebuild needed. The rules live in `android/app/src/main/kotlin/com/ewbrother/app/detect/DetectionRules.kt`.

## Updating later

Bump `version:` in `pubspec.yaml` (for example `1.0.1+2`), build with the **same key** (step 7 "new EC2" note), and install over the old app. Data is kept: the database uses versioned migrations.
