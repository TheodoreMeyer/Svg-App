<p align="center">
  <img src="assets/images/icon.png" alt="Simple Voice App icon" width="96" height="96">
</p>

# Simple Voice App

Simple Voice App is a Flutter Android companion app for SimpleVoice-Geyser. It lets Bedrock players join voice chat and server chat from an Android device without using the browser WebUI.

Current app version: `1.0.0+1`.

## Current Features

- Android-first Flutter app with a short opening splash.
- Server, username, and password join screen with inline validation.
- Password visibility toggle and optional secure password storage.
- Direct websocket connection to the SimpleVoice-Geyser `/ws` route.
- Android native microphone capture with `AudioRecord`.
- Android native PCM playback with `AudioTrack`.
- Phone earpiece and speaker output toggle.
- Open mic, mute, and push-to-talk controls.
- Foreground call notification with mute, speaker, hang up, and inline chat reply actions.
- Voice and Chat tabs after joining.
- Local Test Audio monitor for microphone/playback checks.
- Diagnostics panel with connection, websocket, audio route, native audio devtools, frame counters, mic counters, and chat counters.

## Requirements

- Flutter installed locally.
- Android SDK and a physical Android device for reliable voice testing.
- A SimpleVoice-Geyser server exposing the app/web websocket route.
- Microphone permission granted for sending voice.

## Connection

The app derives the websocket route from the server field.

Examples:

```text
server.com                -> wss://server.com/ws
mc.server.com             -> wss://mc.server.com/ws
server.com/voice/         -> wss://server.com/voice/ws
http://192.168.1.91:24455 -> ws://192.168.1.91:24455/ws
```

For local testing, enter the SimpleVoice-Geyser web/app port, not the Minecraft gameplay port. If the field uses `:25565`, the app shows an inline warning because that is usually the Minecraft server port.

For host-only public addresses, the app can also read discovery metadata from:

```text
https://<host>/.well-known/simplevoice-geyser.json
```

If discovery is not available, the app falls back to `wss://<host>/ws`.

## Audio Behavior

- Incoming legacy PCM is played through native Android playback.
- `svg-v2` PCM frames are parsed and played.
- `svg-v2` Opus frames are counted in diagnostics but are not decoded in this app version.
- Incoming stereo PCM is preserved on stereo-capable output routes.
- Earpiece output is treated as mono-safe so one side of spatial audio is not lost.
- Speaker mode uses the media-style speaker path for normal usable volume.
- Mic send uses mono PCM16 packets from Android microphone capture.

## Chat

The app sends trimmed plain text chat messages after authentication. Empty messages are ignored. Incoming server chat, status, and error messages are shown in the Chat tab timeline.

## Notifications

While connected, the Android foreground notification keeps the call active when the app is backgrounded. It provides quick actions for mute/unmute, speaker/earpiece, hang up, and inline chat replies using Android notification `RemoteInput`.

## Diagnostics

The diagnostics button opens a compact text panel for bug reports and manual testing. It excludes passwords and raw audio. It includes:

- Server and websocket URL.
- Connection state and last close reason.
- Selected audio mode and decoder status.
- Native audio mode, preferred playback device, media/call volume, and route errors.
- Received frame counters and last PCM peak.
- Mic packet count and chat counters.

## Download

Most users should install the app from the latest GitHub Release. Download the newest `.apk` attached to the release, install it on your Android device, and grant microphone and notification permissions when prompted.

## Build form source

```powershell
C:\tools\flutter\bin\flutter.bat pub get
C:\tools\flutter\bin\flutter.bat test
C:\tools\flutter\bin\flutter.bat analyze
C:\tools\flutter\bin\flutter.bat build apk --debug
```

The debug APK is generated under:

```text
build/app/outputs/flutter-apk/
```

## Manual Test Checklist

1. Install the debug APK on a physical Android device.
2. Join a SimpleVoice-Geyser server.
3. Confirm chat sends and receives.
4. Confirm incoming voice plays.
5. Confirm open mic sends voice.
6. Confirm mute stops outbound voice while receive audio and chat continue.
7. Confirm push-to-talk sends only while held.
8. Toggle Speaker and confirm playback changes route and volume.
9. Background the app and test notification actions.
10. Open Diagnostics and confirm it contains route/audio details without passwords.
11. Leave the call and confirm audio, notification, and websocket stop cleanly.

## Repository Notes

This repository should contain only the Flutter/Android app source, assets, tests, build configuration, README, and license. Local generated files, IDE state, agent folders, signing keys, APK/AAB outputs, and planning handoff notes are intentionally ignored.
