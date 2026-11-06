import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/services/place_lookup_service.dart';
import 'package:fsa_app/core/widgets/address_search_field.dart';

/// Searching for a facility by name instead of typing its address
/// (Ethan, 2026-10-08): "Pick n Pay Lynnwood" fills the address box.
///
/// The search runs on the Agency's own server, under the inspector's token,
/// so the Google key never ships on a tablet. The rules that matter are not
/// the search itself but what happens when it is not there: inspectors work
/// out of signal for most of a day, and a helper that took the typed field
/// away would stop the job.
void main() {
  // The field shows a spinner while it looks, and a spinner animates for
  // ever, so pumpAndSettle never returns. Pump a fixed stretch instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<String?> signedIn() async => 'jwt-token';

  PlaceLookupService serviceReturning(String body, {int status = 200}) =>
      PlaceLookupService(
        baseUrl: 'https://fsa.example',
        token: signedIn,
        enabled: true,
        client: MockClient((_) async => http.Response(body, status,
            headers: {'content-type': 'application/json'})),
      );

  const oneSuggestion = '''
  {"suggestions":[{"place_id":"abc123","primary":"Pick n Pay",
                   "secondary":"Lynnwood Road, Pretoria"}]}
  ''';

  group('the lookup', () {
    test('is unavailable with nobody signed in, so the form stays as it was',
        () {
      expect(PlaceLookupService(baseUrl: 'https://fsa.example', enabled: true).isAvailable,
          isFalse);
      expect(
          PlaceLookupService(
              baseUrl: 'https://fsa.example', token: signedIn, enabled: true)
              .isAvailable,
          isTrue);
    });

    test('reads the suggestions the server returns', () async {
      final found = await serviceReturning(oneSuggestion)
          .suggest('Pick n Pay Lynn', sessionToken: 's');

      expect(found, hasLength(1));
      expect(found.single.primary, 'Pick n Pay');
      expect(found.single.secondary, 'Lynnwood Road, Pretoria');
      expect(found.single.placeId, 'abc123');
    });

    test('asks our own server, as the inspector, with where they are',
        () async {
      late http.Request sent;
      final service = PlaceLookupService(
        baseUrl: 'https://fsa.example',
        token: signedIn,
        enabled: true,
        client: MockClient((request) async {
          sent = request;
          return http.Response(oneSuggestion, 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      await service.suggest('Pick n Pay',
          sessionToken: 'tok', nearLatitude: -25.75, nearLongitude: 28.23);

      expect(sent.url.host, 'fsa.example',
          reason: 'the Google key stays on the server, never in the APK');
      expect(sent.url.path, '/api/places/suggest/');
      expect(sent.headers['Authorization'], 'Bearer jwt-token');
      expect(sent.url.queryParameters['session'], 'tok',
          reason: 'one session is billed once, not per keystroke');
      expect(sent.url.queryParameters['lat'], '-25.75');
      expect(sent.url.queryParameters['lng'], '28.23');
    });

    test('says nothing rather than throwing when it cannot reach the server',
        () async {
      final offline = PlaceLookupService(
        baseUrl: 'https://fsa.example',
        token: signedIn,
        enabled: true,
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(await offline.suggest('Pick n Pay', sessionToken: 's'), isEmpty);
    });

    test('says nothing when the allowance is spent', () async {
      expect(
          await serviceReturning('{"suggestions":[]}')
              .suggest('Pick n Pay', sessionToken: 's'),
          isEmpty);
    });

    test('ignores a half-typed word', () async {
      expect(
          await serviceReturning(oneSuggestion).suggest('Pi', sessionToken: 's'),
          isEmpty);
    });
  });

  group('the field', () {
    Future<void> pump(WidgetTester tester, TextEditingController controller,
        PlaceLookupService service) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressSearchField(
            controller: controller,
            service: service,
            // Standing at the facility. Given here so the field does not
            // reach for a GPS fix there is no plugin for in a test.
            nearLatitude: -25.765,
            nearLongitude: 28.282,
            child: TextField(controller: controller),
          ),
        ),
      ));
    }

    testWidgets('offers the match, and filling it leaves it editable',
        (tester) async {
      final controller = TextEditingController();
      await pump(
        tester,
        controller,
        PlaceLookupService(
          baseUrl: 'https://fsa.example',
          token: signedIn,
          enabled: true,
          client: MockClient((request) async => http.Response(
              request.url.path.contains('suggest')
                  ? oneSuggestion
                  : '{"address":"Lynnwood Rd, Pretoria, 0081"}',
              200,
              headers: {'content-type': 'application/json'})),
        ),
      );

      controller.text = 'Pick n Pay Lynnwood';
      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester);
      expect(find.text('Pick n Pay'), findsOneWidget);

      await tester.tap(find.text('Pick n Pay'));
      await settle(tester);

      expect(controller.text, 'Lynnwood Rd, Pretoria, 0081');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the address stays a box the inspector can correct');
    });

    testWidgets('signed out, it is just the typed field', (tester) async {
      final controller = TextEditingController();
      await pump(tester, controller,
          PlaceLookupService(baseUrl: 'https://fsa.example', enabled: true));

      controller.text = 'Pick n Pay Lynnwood';
      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester);

      expect(find.byType(ListTile), findsNothing);
      expect(controller.text, 'Pick n Pay Lynnwood',
          reason: 'what was typed is kept, exactly as before');
    });
  });
}

/// Stands in for a dropped connection.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
