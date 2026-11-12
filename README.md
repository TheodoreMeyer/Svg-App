<p align="center">
  <img src="assets/images/icon.png" alt="Svg-App icon" width="96" height="96">
</p>

# Svg-App

Svg-App is the official Android companion for [SimpleVoice-Geyser](https://github.com/TheodoreMeyer/SimpleVoice-Geyser), bringing voice and server chat to Bedrock players.

## What's new in 1.1.0

- **Opus audio:** native Opus microphone encoding and `svg-v2` spatial playback, using your phone's built-in codecs, with PCM fallback when the server allows it.
- **Minecraft-inspired UI:** Now the svg-app matches the UI from the Simple Voice Geyser plugin, with textured backgrounds, beveled controls, and dedicated Voice and Chat tabs.
- **Four languages:** English, Polski, Italiano, and Español. By default and if it's available, the svg-app will follow your device language, otherwise, you can choose one of the current available options and switch during a call without having to reconnect.
- **Improved push-to-talk:** inline hold-to-talk and fullscreen controls, with screen-reader support.
- **Localized notifications:** mute, change audio output, reply to chat, or leave the call from Android's notification controls.
- **Connection updates:** support for SimpleVoice-Geyser 0.1.5 and Velocity server switching, alongside existing 0.1.4 and 0.1.3 compatibility.
- **Reliable connections:** the app detects your server's version automatically, reconnects after a dropped connection, and tells you when your phone has no internet connection or when a server does not allow the app.
- **Clearer call controls:** connection status, microphone and playback details, and a live diagnostics panel, with layouts that accommodate large text and landscape.
- **App optimization:** Previously the app had unnecessary architecture compatibility, this has been dropped and it's now lighter for all devices.

**Note:** This new version also fixed an ID issue on the app, if you update as is, you will have 2 installations on your device; 1.0.2 and 1.1.0. Make sure to delete the previous one before updating to this newest version. Your saved servers and passwords are not carried over, so you will need to enter them again.

**Disclaimer:** This will only happen on this version, any future releases after 1.1.0 will install as updates correctly.

## Download
For most users, you should just download the latest apk available from [Releases](https://github.com/TheodoreMeyer/Svg-App/releases) and follow step 2 below.

## Getting started

Requires **Android 7.0 or later** and a SimpleVoice-Geyser server (0.1.3, 0.1.4 or 0.1.5) with app/web access enabled. Opus microphone audio needs a 0.1.5 server and a phone whose built-in codec supports it, typically Android 10 or later; otherwise the app uses PCM where the server allows it.

1. Install an APK (always recommended to install latest) from [Releases](https://github.com/TheodoreMeyer/Svg-App/releases), or build it from source.
2. Enter the server's web address, username, and password. Use the SimpleVoice-Geyser web port, not the Minecraft gameplay port.
3. Tap **Join**, grant microphone permission to speak, and choose Open mic or push-to-talk.

You can save your credentials, test your microphone before joining, and switch between speaker and phone earpiece. Voice and chat controls remain accessible from either tab.

PTT stops when the app is backgrounded. The notification's **Unmute** action enables Open mic so you can speak while the app is in the background.


## Build from source

With Flutter and the Android SDK installed, run from the project directory:

```sh
flutter pub get
flutter build apk --release --target-platform=android-arm64 --split-debug-info=build/symbols/arm64-v8a
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`. Keep the matching files from `build/symbols/arm64-v8a/` for crash diagnosis. Release builds are signed with the project's private release key, which is not part of this repository. To build a release yourself, put your own keystore and a `key.properties` file (`storeFile`, `keyAlias`, `storePassword`, `keyPassword`) in a `signing` folder next to the project folder; without it the release build stops with a missing-keystore error. Debug builds need no key.

## Credits

Textures and shared wording are credited in [assets/NOTICE.md](assets/NOTICE.md). Press Start 2P is bundled under the [SIL Open Font License](assets/fonts/OFL.txt).