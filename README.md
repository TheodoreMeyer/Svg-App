<p align="center">
  <img src="assets/images/icon.png" alt="Svg-App icon" width="96" height="96">
</p>

# Svg-App

Svg-App is the official Android companion app for SimpleVoice-Geyser, built with Flutter. It lets Bedrock players join voice chat and server chat from an Android device without using the browser WebUI.

Current development version: **`1.1.0+4`** (`1.1.0` on Android, build number `4`).

[Source repository](https://github.com/TheodoreMeyer/Svg-App) ·
[Report an issue](https://github.com/TheodoreMeyer/Svg-App/issues)

Existing `0.1.4` and `0.1.3` compatibility is retained. Connection and two-way
voice were successfully tested against a `0.1.5` development JAR containing
Velocity and encoding work. Final `0.1.5` release acceptance and backend-transfer
testing of this app build remain pending.

## What's new in 1.1.0

- A native Flutter Minecraft-inspired interface with bundled dirt and stone
  textures, beveled panels and buttons, and pixel headings.
- English, Polish, Italian, and Spanish, with device-language selection by
  default, a saved manual override, and live switching during calls.
- Localized Android notification controls and accessibility labels.
- Ordered plugin compatibility targets `0.1.5 → 0.1.4 → 0.1.3`, an authentication
  deadline for each attempt, and cancellation of late connection results.
- Temporary Velocity transfer handling that keeps the call screen and chat
  draft, pauses outgoing voice/chat, and resumes after backend authentication.
- Inline hold-to-talk and fullscreen PTT, with screen-reader activation and
  PTT transmission cancellation when the app leaves the foreground.

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
- Voice and Chat tabs with shared microphone, output, and PTT controls.
- Inline hold-to-talk and fullscreen PTT with screen-reader activation.
- Temporary backend transfers retain the call and drafts, pause voice/chat
  transmission, and require a fresh PTT press after authentication resumes.
- Local Test Audio monitor for microphone/playback checks.
- Separate diagnostics sheet with connection, websocket, audio route, native audio details, frame counters, mic counters, and chat counters.

## Interface and accessibility

The join screen groups server, username, and password in a compact beveled
panel. It retains inline validation, the Minecraft-port warning, password
visibility, Remember password, output selection, and the local audio self-test.
The globe button opens language selection before or during a call.

The connected screen shows player/server identity and connection status above
Voice and Chat tabs. Microphone mute, output route, transmit mode, and PTT stay
accessible from either tab. Diagnostics opens separately instead of filling
the chat area. The displayed server identity is the entered server address;
it is not a live name for the current Velocity backend.

Press Start 2P is used for short headings and buttons; forms and chat use native
sans-serif text. Standard platform icons, wrapping labels, scrollable layouts,
48dp minimum control targets, large-text support, keyboard clearance, and
reduced-motion behavior keep the themed UI usable on Android. Status-bar icon
contrast follows the dark join background and light connected app bar.

Touch PTT transmits while held and stops on release or cancellation. With a
screen reader, activate the PTT control to start talking and activate it again
to stop; keyboard activation uses the same toggle. Leaving the foreground or
starting a transfer clears active PTT. Fullscreen PTT temporarily enables the
microphone and switches to PTT; closing it restores the previous mute and
transmit-mode settings.

## Languages

Choose **System**, **English**, **Polski**, **Italiano**, or **Español**. System
follows the device language and falls back to English when unsupported. Manual
selection persists in secure storage; selecting System removes the override.
Changing language during a call updates the app and notification without
reconnecting or resetting the draft, mute state, output route, or transmit mode.

App-owned validation, connection/audio errors, dynamic status text, controls,
and accessibility labels are localized. Player chat, unknown server messages,
and protocol values retain their original content. Technical diagnostics stay
in English so bug reports can be compared across languages.

## Download

Most users should install the app from the latest GitHub Release. Download the newest `.apk` attached to the release, install it on your Android device, and grant microphone and notification permissions when prompted.

## Requirements

- An Android device with at least Android 7.0.
- A SimpleVoice-Geyser server exposing the app/web websocket route.
- Microphone permission granted for sending voice.

Building from source additionally requires Flutter, the Android SDK, and a
physical Android device for reliable voice and output-route testing.

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

### Authentication and fallback

The app sends a join containing username, password, and
`clientType: {type: "Svg-App", serverVersion: "0.1.5"}`. The compatibility
version is a plugin target, never the app release version. There are no legacy
`client`, `build`, or `serverBuild` fields in this join.

If the initial unauthenticated connection closes with exactly
`4008 / app_protocol_unsupported`, another connection tries `0.1.4`, then
`0.1.3`: at most three version attempts. Wrong credentials, other close tuples,
manual disconnects, and errors after authentication do not trigger this version
fallback. Only the exact retryable compatibility error packet is suppressed
while another target remains. Final rejection still reaches the UI, so an
unsupported server shows the update-required message.

Each attempt rearms an eight-second authentication deadline, including socket
connection time for that attempt. Timeout or Cancel invalidates pending
connections; a late socket cannot join or reopen the call. Native audio and the
foreground notification start after initial authentication. Capabilities are
sent once per app connection after authentication, with conservative legacy
audio advertisement. Repeated authenticated statuses do not restart audio or
resend capabilities.

### Velocity transfers

After authentication, the exact server status `Changing server` is treated as
a temporary backend transfer. The outer WebSocket and call screen remain open;
outgoing microphone packets and chat are blocked while the next backend becomes
ready. Drafts, mute state, output route, and transmit mode remain intact.
Notification replies are also blocked during this interval.

An authenticated `Connected as…` status resumes sending. Open mic can resume
automatically if enabled and unmuted; PTT requires a fresh activation. The app
does not restart its audio engine or notification service, or resend its
capabilities on transfer completion. A real socket close ends the call.

## Audio Behavior

- Incoming legacy PCM is played through native Android playback.
- `svg-v2` PCM frames are parsed and played.
- `svg-v2` Opus frames are counted in diagnostics but are not decoded in this app version.
- Incoming stereo PCM is preserved on stereo-capable output routes.
- Earpiece output is treated as mono-safe so one side of spatial audio is not lost.
- Speaker mode uses the media-style speaker path for normal usable volume.
- Mic send uses mono PCM16 packets from Android microphone capture.

Microphone capture is 48 kHz PCM16LE mono, sent as 1,920-byte packets (20 ms).
The app advertises only `legacy`, with Opus decoder support disabled. Its
successful test against the encoding rewrite validates the retained Android PCM
path; it does not mean the app sends WebCodecs Opus or advertises full `svg-v2`.
Mute stops outbound capture; incoming audio and chat remain available.

Test audio plays the local microphone back through the selected output without
connecting to a server. It stops when disabled or when the call authenticates.
If microphone permission is denied, listening and chat remain usable.

## Chat

The app sends trimmed plain text chat messages after authentication. Empty
messages are ignored. Chat and unknown server messages retain their original
wording. Connection status is shown above the tabs; errors use localized alerts.
Technical details remain in the separate diagnostics sheet in English.

## Notifications

While connected, the Android foreground notification keeps the call active when the app is backgrounded. It provides quick actions for mute/unmute, speaker/earpiece, hang up, and inline chat replies using Android notification `RemoteInput`.
Notification labels follow the selected language; action identifiers stay stable.

The Flutter bridge supplies translated titles, statuses, action labels, reply
hints, and channel text to the native service. Language changes update the
active notification. Existing notification-unmute behavior is preserved: it
enables Open mic even when the in-app setting is PTT, allowing background voice
control. Mute stops it; changing the transmit mode clears that override.
Backgrounding cancels an active PTT press but does not end an Open mic call.

## Diagnostics

The diagnostics button opens a compact text panel for bug reports and manual testing. It excludes passwords and raw audio. It includes:

- Server and websocket URL.
- Connection state and last close reason.
- Selected audio mode and decoder status.
- Native audio mode, preferred playback device, media/call volume, and route errors.
- Received frame counters and last PCM peak.
- Mic packet count and chat counters.

## Development workspace

`main` is the official-release branch in `D:\Proyectos\simple-voice-android`.
Development uses the linked `dev` worktree at `dev-branch`. The nested tree is
excluded locally through `.git/info/exclude`; keep `.claude/` uncommitted.
Run development commands in `dev-branch` so generated artifacts stay separate.
Test on a device before committing or publishing this milestone. Promotion uses
a tested `dev → main` release PR; remote publication is a separate action.
The Android application ID and namespace remain `com.example.simple_voice_app`
for compatibility with existing installations. The internal Dart package and
native channel identifiers remain stable; user-visible branding is Svg-App.
Release builds currently use debug signing. Production signing requires separate
configuration with the appropriate existing release identity.

## Build from source

```powershell
Set-Location D:\Proyectos\simple-voice-android\dev-branch
C:\tools\flutter\bin\flutter.bat pub get
C:\tools\flutter\bin\flutter.bat test
C:\tools\flutter\bin\flutter.bat analyze
C:\tools\flutter\bin\flutter.bat build apk --debug
```

The debug APK is generated under:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Flutter generates localization classes during `pub get` and builds. When editing
translations, update all four `lib/l10n/app_*.arb` catalogs and run
`flutter gen-l10n`; do not edit `lib/l10n/generated/` manually. Generated
localizations, build outputs, and Android local properties are ignored.
Android Gradle takes `versionName` and `versionCode` from `pubspec.yaml`.

## Implementation map

| Files | Responsibility |
|---|---|
| `lib/main.dart` | Screens, language switching, connection deadlines/cancellation, call/transfer lifecycle, audio gates, chat, and notification updates. |
| `lib/src/ui/minecraft_widgets.dart` | Theme, dirt background, beveled panels, stone buttons, and accessible hold-to-talk behavior. |
| `lib/src/protocol/packets.dart`, `simple_voice_client.dart`, `connection_policy.dart` | Join/capability payloads, ordered version fallback, exact error suppression, transfer transmission guards, and close handling. |
| `lib/src/protocol/connection_target.dart` | Address validation, discovery, and WebSocket URL resolution. |
| `lib/l10n/app_*.arb`, `l10n.yaml` | Four-language catalogs and Flutter localization generation. |
| `lib/src/settings/credential_store.dart` | Existing saved server/username/optional password and the new saved language override. Credential keys are preserved. |
| `lib/src/notification/call_notification_bridge.dart`, Android `CallNotificationService.kt` | Localized notification payload and native foreground controls; existing action IDs remain stable. |
| `lib/src/audio/`, Android `MainActivity.kt` | Existing microphone capture, PCM parsing/playback, output routing, and native method/event channels. |
| `lib/src/diagnostics.dart` | English technical state, audio/chat counters, and redacted diagnostics. |

## Automated verification

The suite covers all three supported target paths, final unsupported rejection,
excluded retries, post-auth capability timing, per-attempt deadlines, late
connection cancellation, transfer transmission gates, repeated statuses,
draft/control preservation, PTT touch/cancellation and accessibility activation,
locale persistence and live switching, notification actions/label payloads, and
existing audio/credential behavior.

Layout tests exercise all four languages in 320×640 portrait and 640×320
landscape at 200% text scale, including chat keyboard clearance and fullscreen
PTT. These are simulated Flutter checks; physical-device audio, native
notification behavior, and final upstream acceptance require the checklist
below. Voice/controller key binding, saved server profiles, QR joining, unread
chat badges, and full Opus support are outside this milestone.

## Physical-device acceptance and troubleshooting

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
12. Connect directly to supported `0.1.4` and `0.1.3` servers. Confirm an
    unsupported server still shows the update-required message after all targets.
13. Using the final `0.1.5` implementation, transfer through Velocity between
    two backends. Keep a draft, hold PTT, and verify transmission pauses until
    reauthentication. PTT must require a fresh press; mute/route/mode must persist.
14. Repeat transfers while backgrounded; exercise notification mute, route,
    chat reply, and hang-up actions. Confirm capabilities are sent only once
    by the app and audio does not restart on repeated authenticated statuses.
15. Switch all four languages during a call, then relaunch to check persistence.
    Select System to restore device-language behavior and English fallback.
16. Check small screens, landscape, large text, keyboard clearance, reduced
    motion, TalkBack activation, and PTT cancellation when backgrounding.

Asset and shared wording attribution is in [assets/NOTICE.md](assets/NOTICE.md).
The bundled font's SIL Open Font License is in [assets/fonts/OFL.txt](assets/fonts/OFL.txt).

