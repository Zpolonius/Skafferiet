import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/core/providers/connectivity_provider.dart';
import 'package:skafferiet/shared/widgets/offline_banner.dart';

void main() {
  Widget createWidgetUnderTest(NetworkStatus status) {
    return ProviderScope(
      overrides: [
        connectivityProvider.overrideWith((ref) => _StaticConnectivityNotifier(status)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('App indhold'),
          ),
          bottomNavigationBar: OfflineBanner(),
        ),
      ),
    );
  }

  testWidgets('OfflineBanner is hidden when status is online', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(NetworkStatus.online));
    await tester.pumpAndSettle();

    expect(find.text('Offline-tilstand – ændringer gemmes og synkroniseres'), findsNothing);
    expect(find.text('Forbindelse genoprettet – synkroniserer...'), findsNothing);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
  });

  testWidgets('OfflineBanner displays warning message and icon when offline', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(NetworkStatus.offline));
    await tester.pumpAndSettle();

    expect(find.text('Offline-tilstand – ændringer gemmes og synkroniseres'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('OfflineBanner displays restored message and icon when reconnected', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(NetworkStatus.reconnected));
    await tester.pumpAndSettle();

    expect(find.text('Forbindelse genoprettet – synkroniserer...'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });
}

class _StaticConnectivityNotifier extends StateNotifier<NetworkStatus>
    implements ConnectivityNotifier {
  _StaticConnectivityNotifier(super.state);

  @override
  Duration get reconnectDisplayDuration => const Duration(seconds: 3);
}
