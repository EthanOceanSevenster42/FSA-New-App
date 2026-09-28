import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/poultry/domain/quid_flow.dart';

/// The QUID stage rules, as the original's weighing screen applies them.
void main() {
  QuidStageSample carcass({
    String initial = '1000',
    String waterFinal = '',
    int? injector,
    String injectorAfter = '',
    String quidPercent = '',
  }) =>
      (
        initial: initial,
        waterFinal: waterFinal,
        injector: injector,
        injectorAfter: injectorAfter,
        quidPercent: quidPercent,
      );

  test('the stages open in order', () {
    expect(
        quidStage(
            chillingComplete: false,
            injectorComplete: false,
            determinationComplete: false),
        QuidStage.chilling);
    expect(
        quidStage(
            chillingComplete: true,
            injectorComplete: false,
            determinationComplete: false),
        QuidStage.injector);
    expect(
        quidStage(
            chillingComplete: true,
            injectorComplete: true,
            determinationComplete: false),
        QuidStage.determination);
    expect(
        quidStage(
            chillingComplete: true,
            injectorComplete: true,
            determinationComplete: true),
        QuidStage.finished);
  });

  test('water pick-up is allowed up to 7%, not over', () {
    expect(quidWaterPickupPasses('7.000'), isTrue);
    expect(quidWaterPickupPasses('7.001'), isFalse);
    expect(quidWaterPickupPasses(''), isFalse);
  });

  test('regulated QUID is 10% whole carcass, 15% cuts', () {
    expect(quidRegulatedPercent(isWholeCarcass: true), 10);
    expect(quidRegulatedPercent(isWholeCarcass: false), 15);
  });

  group('closing chilling', () {
    test('water needs five carcasses weighed off the chiller', () {
      final four = List.generate(4, (_) => carcass(waterFinal: '1020'));
      expect(quidChillingBlocked(four, isWaterChilled: true), isNotNull);
      final five = [...four, carcass(waterFinal: '1020')];
      expect(quidChillingBlocked(five, isWaterChilled: true), isNull);
    });

    test('air needs five carcasses weighed in', () {
      final five = List.generate(5, (_) => carcass());
      expect(quidChillingBlocked(five, isWaterChilled: false), isNull);
      expect(quidChillingBlocked(five.sublist(1), isWaterChilled: false),
          isNotNull);
    });
  });

  test('closing the injector stage needs five on every injector', () {
    final onOne = List.generate(
        5, (_) => carcass(injector: 1, injectorAfter: '1100'));
    expect(quidInjectorBlocked(onOne, [1]), isNull);
    expect(quidInjectorBlocked(onOne, [1, 2]), isNotNull,
        reason: 'injector 2 has none');
  });

  test('closing the determination needs five QUID figures per injector', () {
    final done = List.generate(
        5, (_) => carcass(injector: 1, quidPercent: '7.407'));
    expect(quidDeterminationBlocked(done, [1]), isNull);
    expect(quidDeterminationBlocked(done.sublist(1), [1]), isNotNull);
  });

  test('a failure repeats on the first round and rejects on the second', () {
    expect(quidOnFailure(1), QuidFailureStep.repeat);
    expect(quidOnFailure(2), QuidFailureStep.reject);
  });

  test('only the last round is judged', () {
    final rows = [(1, 'a'), (1, 'b'), (2, 'c')];
    expect(quidLastRound(rows, (r) => r.$1).map((r) => r.$2), ['c']);
    expect(quidLastRound(<(int, String)>[], (r) => r.$1), isEmpty);
  });

  test('verification records survive being stored, photograph and all', () {
    final records = [
      QuidVerificationRecord(
        date: DateTime(2026, 9, 20),
        documentName: 'Injector log 14',
        verified: true,
        deviationPresent: true,
        deviationComment: 'Two entries unsigned',
        photoPath: '/photos/doc_1.jpg',
      ),
    ];
    final back =
        QuidVerificationRecord.decode(QuidVerificationRecord.encode(records));
    expect(back.single.documentName, 'Injector log 14');
    expect(back.single.date, DateTime(2026, 9, 20));
    expect(back.single.verified, isTrue);
    expect(back.single.deviationComment, 'Two entries unsigned');
    expect(back.single.photoPath, '/photos/doc_1.jpg');
    expect(back.single.hasPhoto, isTrue);
    expect(QuidVerificationRecord.decode(''), isEmpty);
    expect(QuidVerificationRecord.decode('not json'), isEmpty);
    // A record from before the photograph was kept reads back without one.
    expect(
        QuidVerificationRecord.decode('[{"document_name":"Old"}]')
            .single
            .hasPhoto,
        isFalse);
  });

  test('a rejection needs two photographs; without one, none are asked for',
      () {
    // The original's MinDirectionPhotos, taken from the rejection block.
    expect(quidMinRejectionPhotos, 2);
    expect(quidRejectionPhotosOutstanding(0), isTrue);
    expect(quidRejectionPhotosOutstanding(1), isTrue);
    expect(quidRejectionPhotosOutstanding(2), isFalse);
  });
}
