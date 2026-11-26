import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/main.dart';
import 'package:meshhub_flutter/mesh_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('all four palettes keep text and button labels readable', () {
    expect(MeshHubTheme.values.map((t) => t.label), [
      'Firesky',
      'Cyberpunk',
      'Retro 82',
      'Bliss',
    ]);
    for (final choice in MeshHubTheme.values) {
      final p = choice.palette;
      expect(
        contrast(p.text, p.panel),
        greaterThanOrEqualTo(4.5),
        reason: choice.label,
      );
      expect(
        contrast(p.muted, p.panel),
        greaterThanOrEqualTo(4.5),
        reason: choice.label,
      );
      final scheme = p.buildTheme().colorScheme;
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
        reason: choice.label,
      );
    }
  });

  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    testWidgets('four themes render and switch at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final export = Platform.environment['MESHHUB_THEME_PREVIEWS'];
      if (export != null) {
        await tester.runAsync(() async {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          for (final font in {
            'Ahem': '/usr/share/fonts/liberation/LiberationSans-Regular.ttf',
            'Roboto': '/usr/share/fonts/liberation/LiberationSans-Regular.ttf',
            'monospace':
                '/usr/share/fonts/ttf-ia-writer/iAWriterMonoS-Regular.ttf',
          }.entries) {
            final loader = FontLoader(font.key);
            loader.addFont(
              File(font.value).readAsBytes().then(ByteData.sublistView),
            );
            await loader.load();
          }
        });
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: const MeshHubApp()),
      );
      await tester.pumpAndSettle();
      final backgrounds = <Color>{};
      for (final choice in MeshHubTheme.values) {
        await tester.tap(find.byTooltip('Theme'));
        await tester.pumpAndSettle();
        for (final retired in ['light', 'dark', 'tactical']) {
          expect(find.text(retired), findsNothing);
        }
        await tester.tap(find.text(choice.label).last);
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.byType(Scaffold).first));
        backgrounds.add(theme.scaffoldBackgroundColor);
        expect(theme.scaffoldBackgroundColor, choice.palette.background);
        expect(tester.takeException(), isNull);
        if (export != null) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final folder = Directory(export);
            await folder.create(recursive: true);
            await File(
              '${folder.path}/${choice.name}-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      expect(backgrounds, hasLength(4));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
