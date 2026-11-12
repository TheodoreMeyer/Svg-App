import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/ui/minecraft_widgets.dart';

void main() {
  testWidgets(
    'screen reader can start and stop PTT and transfer stops a latched press',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final available = ValueNotifier(true);
      addTearDown(available.dispose);
      final talking = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HoldToTalk(
              available: available,
              enabled: true,
              label: 'Hold to Talk',
              talkingLabel: 'Talking',
              hint: 'Activate to start or stop talking',
              onTalkingChanged: talking.add,
            ),
          ),
        ),
      );
      var node = tester.getSemantics(find.byType(HoldToTalk));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(talking, [true]);
      node = tester.getSemantics(find.byType(HoldToTalk));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(talking, [true, false]);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      available.value = false;
      await tester.pump();
      expect(talking, [true, false, true, false]);
      available.value = true;
      await tester.pump();
      expect(talking.last, false);
      expect(
        tester.getSize(find.byType(HoldToTalk)).height,
        greaterThanOrEqualTo(48),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a held finger keeps talking while it moves inside the zone, stops outside it, and never scrolls',
    (tester) async {
      final available = ValueNotifier(true);
      addTearDown(available.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final talking = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 300),
                  HoldToTalk(
                    available: available,
                    enabled: true,
                    label: 'Hold to Talk',
                    talkingLabel: 'Talking',
                    hint: 'Activate to start or stop talking',
                    onTalkingChanged: talking.add,
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      final zone = tester.getCenter(find.byType(HoldToTalk));
      final gesture = await tester.startGesture(zone);
      await tester.pump();
      expect(talking, [true]);
      await gesture.moveTo(zone + const Offset(200, 8));
      await tester.pump();
      await gesture.moveTo(zone + const Offset(-200, -8));
      await tester.pump();
      expect(talking, [true]);
      await gesture.moveTo(zone + const Offset(0, 150));
      await tester.pump();
      expect(talking, [true, false]);
      await gesture.moveTo(zone);
      await tester.pump();
      expect(talking, [true, false, true]);
      await gesture.up();
      await tester.pump();
      expect(talking, [true, false, true, false]);
      expect(scroll.offset, 0);
    },
  );
}
