import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

void main() {
  late MockFLauncherChannel channel;
  late MockAppsService appsService;

  setUp(() {
    channel = MockFLauncherChannel();
    appsService = MockAppsService();
    when(appsService.applications).thenReturn([fakeApp(packageName: 'com.netflix.ninja', name: 'Netflix')]);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppsService>.value(
        value: appsService,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RemoteButtonsPage(channel: channel)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks to turn on the service when it is off', (tester) async {
    when(channel.isButtonOverrideServiceEnabled()).thenAnswer((_) async => false);
    when(channel.getButtonOverrides()).thenAnswer((_) async => []);

    await pump(tester);

    expect(find.text('Open accessibility settings'), findsOneWidget);
    expect(find.text('Add a button'), findsNothing);
    await tester.tap(find.text('Open accessibility settings'));
    verify(channel.openAccessibilitySettings());
  });

  testWidgets('lists overrides with button and app names', (tester) async {
    when(channel.isButtonOverrideServiceEnabled()).thenAnswer((_) async => true);
    when(channel.getButtonOverrides()).thenAnswer((_) async => [
          {'keyCode': 4062, 'keyName': '4062', 'packageName': 'com.netflix.ninja'},
          {'keyCode': 183, 'keyName': 'KEYCODE_PROG_RED', 'packageName': ''},
        ]);

    await pump(tester);

    expect(find.text('Add a button'), findsOneWidget);
    expect(find.text('Prog red'), findsOneWidget);
    expect(find.text('Do nothing'), findsOneWidget);
    expect(find.text('Button 4062'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });
}
