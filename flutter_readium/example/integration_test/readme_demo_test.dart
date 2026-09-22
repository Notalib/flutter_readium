import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_example/pages/player.page.dart';
import 'package:flutter_readium_example/state/index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'readium_integration_harness.dart';
import 'test_fixtures.dart';

const _scene = String.fromEnvironment(
  'README_DEMO_SCENE',
  defaultValue: 'epub',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('records the $_scene README demo scene', (tester) async {
    expect(
      const {'epub', 'readalong', 'pdf', 'comic'},
      contains(_scene),
      reason: 'Unknown README demo scene',
    );

    final storageDirectory = await getTemporaryDirectory();
    HydratedBloc.storage = await HydratedStorage.build(
      storageDirectory: HydratedStorageDirectory(
        '${storageDirectory.path}/readme_demo',
      ),
    );
    await HydratedBloc.storage.clear();

    final fixturePaths = await loadFixturePaths();
    final fixtureKey = switch (_scene) {
      'epub' => FixtureKeys.peterRabbitEpub,
      'readalong' => FixtureKeys.overlayWebpub,
      'pdf' => FixtureKeys.timeMachinePdf,
      'comic' => FixtureKeys.comic,
      _ => throw StateError('Unknown README demo scene: $_scene'),
    };
    final fixturePath = fixturePaths[fixtureKey];
    expect(
      fixturePath,
      isNotNull,
      reason: 'Missing generated fixture $fixtureKey',
    );

    final readium = FlutterReadium();
    final textSettingsBloc = TextSettingsBloc()..setDefaultPreferences();
    final ttsSettingsBloc = TtsSettingsBloc();
    final playerControlsBloc = PlayerControlsBloc(
      ttsSettingsBloc: ttsSettingsBloc,
    );
    final publicationBloc = PublicationBloc();
    final locators = <Locator>[];
    final locatorSubscription = readium.onTextLocatorChanged.listen(
      locators.add,
    );

    addTearDown(() async {
      await locatorSubscription.cancel();
      await readium.stop().catchError((_) {});
      await readium.closePublication().catchError((_) {});
      await publicationBloc.close();
      await playerControlsBloc.close();
      await ttsSettingsBloc.close();
      await textSettingsBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: publicationBloc),
          BlocProvider.value(value: textSettingsBloc),
          BlocProvider.value(value: ttsSettingsBloc),
          BlocProvider.value(value: playerControlsBloc),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: PlayerPage(),
        ),
      ),
    );

    publicationBloc.add(OpenPublication(publicationUrl: fixturePath!));
    await waitWithPump(
      tester,
      () => publicationBloc.state.publication != null || publicationBloc.state.error != null,
      timeout: firstMountTimeout,
      reason: 'The demo publication did not open',
    );
    expect(publicationBloc.state.error, isNull);

    await waitWithPump(
      tester,
      () => locators.isNotEmpty,
      timeout: firstMountTimeout,
      reason: 'The demo reader did not emit an initial locator',
    );

    if (_scene == 'readalong') {
      await readium.setDecorationStyle(
        const ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: Colors.yellow,
        ),
        null,
      );
    }

    final publication = publicationBloc.state.publication!;
    if (_scene == 'pdf') {
      final navigated = await readium.goToLocator(
        locators.last.copyWithLocations(position: 2),
      );
      expect(navigated, isTrue, reason: 'Could not open the selected PDF page');
    } else {
      final target = _targetLocator(publication);
      final navigated = await readium.goToLocator(target);
      expect(
        navigated,
        isTrue,
        reason: 'Could not navigate to the selected demo content',
      );
      await waitWithPump(
        tester,
        () => locators.any((locator) => locator.href == target.href),
        timeout: const Duration(seconds: 20),
        reason: 'The reader did not reach the selected demo resource',
      );
    }
    await _hold(tester, const Duration(seconds: 2));

    debugPrintSynchronously('README_DEMO_READY:$_scene');
    switch (_scene) {
      case 'epub':
        await _recordEpubScene(tester);
      case 'readalong':
        await _recordReadAlongScene(tester, playerControlsBloc);
      case 'pdf' || 'comic':
        await _hold(tester, const Duration(seconds: 10));
    }
    expect(tester.takeException(), isNull);
    debugPrintSynchronously('README_DEMO_DONE:$_scene');
    await _hold(tester, const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Locator _targetLocator(Publication publication) {
  if (_scene == 'comic') {
    final resource = publication.readingOrder.length > 1 ? publication.readingOrder[1] : publication.readingOrder.first;
    return publication.locatorFromLink(
          Link(
            href: '${resource.href}#hix00001',
            type: resource.type,
            title: resource.title,
          ),
        ) ??
        (throw StateError('Could not create a locator for the comic page'));
  }

  final resourceName = _scene == 'epub' ? '7451058775928492912_14838-h-0.htm.xhtml' : '38533-0004-generic.xhtml';
  final fragment = _scene == 'epub' ? 'img_images_peter19.jpg' : 'uwlh00026';
  final resource = publication.readingOrder.firstWhere(
    (link) => link.href.endsWith(resourceName),
    orElse: () => throw StateError('Missing demo resource $resourceName'),
  );
  final locator = publication.locatorFromLink(
    Link(
      href: '${resource.href}#$fragment',
      type: resource.type,
      title: resource.title,
    ),
  );
  return locator ??
      (throw StateError(
        'Could not create a locator for $resourceName#$fragment',
      ));
}

Future<void> _recordEpubScene(WidgetTester tester) async {
  await _hold(tester, const Duration(milliseconds: 1200));

  final settingsButton = find.byTooltip('Open visual reader settings');
  expect(settingsButton, findsOneWidget);
  await tester.tap(settingsButton);
  await _hold(tester, const Duration(milliseconds: 700));

  final fontSizeSlider = find.byKey(const ValueKey('font_size_slider'));
  expect(fontSizeSlider, findsOneWidget);
  await _dragHorizontally(tester, fontSizeSlider, 72);
  await _hold(tester, const Duration(milliseconds: 500));

  final themeTab = find.text('Theme');
  expect(themeTab, findsOneWidget);
  await tester.tap(themeTab);
  await _hold(tester, const Duration(milliseconds: 600));

  final themeSwatches = find.text('Aa');
  expect(themeSwatches, findsWidgets);
  await tester.tap(themeSwatches.first);
  await _hold(tester, const Duration(milliseconds: 800));

  await tester.tap(find.byKey(const ValueKey('text_settings_close_button')));
  await _hold(tester, const Duration(milliseconds: 1200));

  final nextPage = find.byTooltip('Skip to next page');
  expect(nextPage, findsOneWidget);
  await tester.tap(nextPage);
  await _hold(tester, const Duration(milliseconds: 1800));
}

Future<void> _recordReadAlongScene(
  WidgetTester tester,
  PlayerControlsBloc playerControlsBloc,
) async {
  await _hold(tester, const Duration(milliseconds: 1200));

  final playButton = find.byTooltip('Play');
  expect(playButton, findsOneWidget);
  await tester.tap(playButton);
  await waitWithPump(
    tester,
    () => playerControlsBloc.state.audioEnabled && playerControlsBloc.state.playing,
    timeout: const Duration(seconds: 30),
    reason: 'Read-along playback did not start',
  );
  await _hold(tester, const Duration(seconds: 6));

  final pauseButton = find.byTooltip('Pause');
  expect(pauseButton, findsOneWidget);
  await tester.tap(pauseButton);
  await waitWithPump(
    tester,
    () => !playerControlsBloc.state.playing,
    timeout: const Duration(seconds: 10),
    reason: 'Read-along playback did not pause',
  );
  await _hold(tester, const Duration(milliseconds: 1200));
}

Future<void> _dragHorizontally(
  WidgetTester tester,
  Finder finder,
  double distance,
) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  const steps = 6;
  for (var step = 1; step <= steps; step++) {
    await gesture.moveBy(Offset(distance / steps, 0));
    await _hold(tester, const Duration(milliseconds: 70));
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _hold(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}
