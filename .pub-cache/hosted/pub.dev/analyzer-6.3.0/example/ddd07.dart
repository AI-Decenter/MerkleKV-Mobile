import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';

void main() async {
  final byteStore = MemoryByteStore();

  {
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
        '/Users/scheglov/Source/flutter/packages/flutter_tools',
      ],
      byteStore: byteStore,
    );

    final timer = Stopwatch()..start();
    for (final analysisContext in collection.contexts) {
      print(analysisContext.contextRoot.root.path);
      final analysisSession = analysisContext.currentSession;
      for (final path in analysisContext.contextRoot.analyzedFiles()) {
        if (path.endsWith('.dart')) {
          print('  $path');
          await analysisSession.getUnitElement(path);
        }
      }
    }
    print('[time: ${timer.elapsedMilliseconds} ms]');
  }

  {
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
        '/Users/scheglov/Source/flutter/packages/flutter_tools',
      ],
      byteStore: byteStore,
    );

    final timer = Stopwatch()..start();
    for (final analysisContext in collection.contexts) {
      print(analysisContext.contextRoot.root.path);
      final analysisSession = analysisContext.currentSession;
      for (final path in analysisContext.contextRoot.analyzedFiles()) {
        if (path.endsWith('.dart')) {
          print('  $path');
          final unitResult = await analysisSession.getUnitElement(path);
          if (unitResult is UnitElementResult) {
            unitResult.element.classes;
            unitResult.element.mixins;
          }
        }
      }
    }
    print('[time: ${timer.elapsedMilliseconds} ms]');
  }
}
