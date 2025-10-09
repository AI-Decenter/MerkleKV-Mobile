import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/main.dart';

void main() {
  group('MerkleKV Demo App Widget Tests', () {
    testWidgets('App renders title and description correctly',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify that the app title is displayed.
      expect(find.text('MerkleKV Mobile Demo'), findsWidgets);
      expect(find.text('Package structure initialized successfully!'),
          findsOneWidget);
    });

    testWidgets('AppBar displays correct title', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify that our AppBar has the correct title.
      expect(find.byType(AppBar), findsOneWidget);
      expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('MerkleKV Mobile Demo'),
          ),
          findsOneWidget);
    });

    testWidgets('Main content is centered correctly',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify that content is properly centered
      expect(find.byType(Center), findsOneWidget);
      expect(find.byType(Column), findsOneWidget);

      // Find the Column widget and verify its mainAxisAlignment
      final Column column = tester.widget(find.byType(Column));
      expect(column.mainAxisAlignment, MainAxisAlignment.center);
    });

    testWidgets('App uses correct theme', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Find the MaterialApp widget and verify its properties
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.title, 'MerkleKV Demo');
      expect(app.theme?.primaryColor, isNotNull);
    });

    testWidgets('Scaffold structure is correct', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify the basic Scaffold structure
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);

      // Verify body contains the expected widgets
      expect(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(Center),
          ),
          findsOneWidget);
    });

    testWidgets('Text widgets have correct styles',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Find text widgets and verify they exist
      expect(find.byType(Text), findsWidgets);

      // Verify that we have the expected text content
      expect(find.text('MerkleKV Mobile Demo'), findsWidgets);
      expect(find.text('Package structure initialized successfully!'),
          findsOneWidget);
    });

    testWidgets('App can be rebuilt without errors',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Rebuild the app
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      // Verify everything still works after rebuild
      expect(find.text('MerkleKV Mobile Demo'), findsWidgets);
      expect(find.text('Package structure initialized successfully!'),
          findsOneWidget);
    });

    testWidgets('Widget tree structure is correct',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify the widget tree structure
      expect(find.byType(MyApp), findsOneWidget);
      expect(find.byType(MyHomePage), findsOneWidget);

      // Check that MyHomePage has the correct title property
      final MyHomePage homePage = tester.widget(find.byType(MyHomePage));
      expect(homePage.title, 'MerkleKV Mobile Demo');
    });
  });

  group('Counter Widget Demo Tests', () {
    // This group demonstrates how to test a more interactive widget
    // For now, we'll create a simple stateful widget test example

    testWidgets('Demo of stateful widget interaction',
        (WidgetTester tester) async {
      int tapCount = 0;

      // Create a simple counter widget for demonstration
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    Text('Tap count: $tapCount'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          tapCount++;
                        });
                      },
                      child: const Text('Tap me'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Verify initial state
      expect(find.text('Tap count: 0'), findsOneWidget);
      expect(find.text('Tap me'), findsOneWidget);

      // Tap the button and verify state change
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Tap count: 1'), findsOneWidget);
      expect(find.text('Tap count: 0'), findsNothing);

      // Tap again to verify multiple interactions
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Tap count: 2'), findsOneWidget);
    });
  });
}
