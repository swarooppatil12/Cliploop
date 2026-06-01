import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cliploops/app.dart';
import 'package:cliploops/providers/music_provider.dart';
import 'package:cliploops/providers/player_provider.dart';

void main() {
  testWidgets('Cliploops home screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MusicProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ],
        child: const CliploopsApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Cliploops'), findsOneWidget);
    expect(find.text('Tap to upload audio'), findsOneWidget);
    expect(find.text('Recent Files'), findsOneWidget);
  });
}
