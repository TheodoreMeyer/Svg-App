import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/main.dart';

const capturePreviews = bool.fromEnvironment('SVG_CAPTURE_PREVIEWS');

void main() {
  for (final locale in ['en', 'pl', 'it', 'es']) {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      testWidgets('$locale fits $size with large text and keyboard', (
        tester,
      ) async {
        FlutterSecureStorage.setMockInitialValues({
          'preferred_language': locale,
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: const SimpleVoiceApp(showOpeningSplash: false),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('joinButton')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: SimpleVoiceApp(
              key: Key('call-$locale'),
              initiallyConnected: true,
              showOpeningSplash: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final chatLabel = {
          'en': 'Chat',
          'pl': 'Czat',
          'it': 'Chat',
          'es': 'Chat',
        }[locale]!;
        await tester.ensureVisible(find.text(chatLabel));
        await tester.tap(find.text(chatLabel));
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('chatInput')));
        await tester.enterText(
          find.byKey(const Key('chatInput')),
          'Untranslated player chat',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('openPttButton')));
        await tester.tap(find.byKey(const Key('openPttButton')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pttHoldZone')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  if (capturePreviews) {
    testWidgets('export native Flutter design previews', (tester) async {
      for (final name in [
        'simple_voice_app/notification_actions',
        'simple_voice_app/mic',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel(name),
            null,
          ),
        );
      }
      await tester.runAsync(() async {
        final pixel = FontLoader('PressStart2P')
          ..addFont(rootBundle.load('assets/fonts/PressStart2P-Regular.ttf'));
        final sans = FontLoader('Roboto')
          ..addFont(
            File(
              'build/Roboto.ttf',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([pixel.load(), sans.load(), icons.load()]);
        await Directory('build/previews').create(recursive: true);
      });
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final context = tester.element(find.byType(Scaffold).first);
          for (final path in [
            'assets/images/icon.png',
            'assets/textures/dirt.png',
            'assets/textures/stone.png',
          ]) {
            await precacheImage(AssetImage(path), context);
          }
        });
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/previews/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: const SimpleVoiceApp(showOpeningSplash: false),
        ),
      );
      await capture('join');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: const SimpleVoiceApp(
            key: Key('preview-call'),
            initiallyConnected: true,
            showOpeningSplash: false,
          ),
        ),
      );
      await capture('voice');
      await tester.tap(find.text('Chat'));
      await capture('chat');
      await tester.tap(find.byKey(const Key('openMicSwitch')));
      await tester.ensureVisible(find.byKey(const Key('openPttButton')));
      await tester.tap(find.byKey(const Key('openPttButton')));
      await capture('ptt');
    });
  }
}
