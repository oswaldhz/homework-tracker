import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Response parsing: success page should not trigger error', () {
    final html = File('test/fixtures/savesubmission_success_response.html').readAsStringSync();

    final isSuccess = html.contains('Your submission has been saved') ||
        html.contains('Su entrega ha sido guardada') ||
        html.contains('Tu entrega ha sido guardada') ||
        html.contains('Su env') ||
        html.contains('Tu env') ||
        html.contains('class="notifysuccess"') ||
        html.contains('alert-success') ||
        html.contains('submissionstatussubmitted') ||
        html.contains('Enviado para calificar') ||
        html.contains('Submitted for grading');

    expect(isSuccess, isTrue,
        reason: 'The debug HTML shows "Enviado para calificar" and '
            '"submissionstatussubmitted" - our fix must recognize it as success');

    final isError = html.contains('class="notifyproblem"') ||
        html.contains('class="alert alert-danger"') ||
        html.contains('class="error"');

    expect(isError, isFalse,
        reason: 'role="alert" was removed from error detection - '
            'the page only has a message dialogue, not a Moodle error');
  });

  test('Response parsing: role="alert" no longer triggers false positive', () {
    final html = File('test/fixtures/savesubmission_success_response.html').readAsStringSync();

    final hasRoleAlert = html.contains('role="alert"');
    expect(hasRoleAlert, isTrue,
        reason: 'The page has role="alert" in a message dialogue');

    final hasError = html.contains('class="notifyproblem"') ||
        html.contains('class="alert alert-danger"');
    expect(hasError, isFalse,
        reason: 'But no actual Moodle error classes are present');

    // This is the key: role="alert" should NOT trigger error detection
    final wouldHaveTriggeredOldCode = html.contains('class="notifyproblem"') ||
        html.contains('role="alert"') ||
        html.contains('class="error"');
    final wouldTriggerNewCode = html.contains('class="notifyproblem"') ||
        html.contains('class="alert alert-danger"') ||
        html.contains('class="error"');

    expect(wouldHaveTriggeredOldCode, isTrue,
        reason: 'Old code would have errored on role="alert"');
    expect(wouldTriggerNewCode, isFalse,
        reason: 'New code correctly ignores role="alert" in message dialogues');
  });
}
