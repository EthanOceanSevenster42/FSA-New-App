// Exercises the version comparison behind the in-app update.
//
//     dart run tool/check_update_version.dart

import 'dart:io';

import 'package:fsa_app/features/updates/domain/published_build.dart';

int _failures = 0;

void check(String what, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (!ok) _failures++;
  stdout.writeln('${ok ? "  ok  " : "  FAIL"}  $what'
      '${ok ? "" : "\n         expected: $expected\n         actual:   $actual"}');
}

void main() {
  stdout.writeln('published build number\n');

  check('read off a published version', PublishedBuild.numberOf('1.0.1+2107'),
      2107);
  check('a version with no build is not an update',
      PublishedBuild.numberOf('1.0.1'), null);
  check('  nor is a trailing plus', PublishedBuild.numberOf('1.0.1+'), null);
  check('  nor is something unparsable', PublishedBuild.numberOf('1.0.1+beta'),
      null);
  check('  nor is an empty string', PublishedBuild.numberOf(''), null);
  check('surrounding space is ignored', PublishedBuild.numberOf('1.0.1+ 2107 '),
      2107);
  check('the last plus wins', PublishedBuild.numberOf('1.0+1+2107'), 2107);

  check('a newer build is offered',
      PublishedBuild.isNewer(published: '1.0.1+2107', running: '2106'), true);
  check('the same build is not offered again',
      PublishedBuild.isNewer(published: '1.0.1+2106', running: '2106'), false);
  check('an older build is never offered',
      PublishedBuild.isNewer(published: '1.0.1+2100', running: '2106'), false);
  check('an unreadable published version offers nothing',
      PublishedBuild.isNewer(published: 'latest', running: '2106'), false);
  check('an unreadable running version offers nothing',
      PublishedBuild.isNewer(published: '1.0.1+2107', running: 'dev'), false);

  stdout.writeln(
      _failures == 0 ? '\nall checks passed' : '\n$_failures check(s) FAILED');
  if (_failures > 0) exitCode = 1;
}
