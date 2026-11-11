import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/services/app_connection_service.dart';

// Mirrors real `lsof +c 0 -i TCP -n -P -F pcnTP` output: the TST= state
// line follows the n= address line.
const _lsof = '''
p100
cComet Helper
f20
PTCP
n10.0.0.5:59936->172.64.146.215:443
TST=ESTABLISHED
TQR=0
f21
PTCP
n10.0.0.5:59937->172.64.146.215:443
TST=ESTABLISHED
f22
PTCP
n10.0.0.5:59938->104.18.26.48:443
TST=CLOSE_WAIT
f23
PTCP
n127.0.0.1:5000->127.0.0.1:6000
TST=ESTABLISHED
f24
PTCP
n*:8080
TST=LISTEN
p200
cComet
f9
PTCP
n10.0.0.5:60000->74.125.197.84:443
TST=ESTABLISHED
p300
cclaude
f5
PTCP
n[2606:4700::1]:443
TST=LISTEN
f6
PTCP
n10.0.0.5:61000->[2606:4700::6810:84e5]:443
TST=ESTABLISHED
''';

const _ps = '''
    1     0 /sbin/launchd
  100   200 /Applications/Comet.app/Contents/Frameworks/Comet Framework.framework/Helpers/Comet Helper.app/Contents/MacOS/Comet Helper
  200     1 /Applications/Comet.app/Contents/MacOS/Comet
  300     1 /Users/me/.local/bin/claude
''';

void main() {
  group('parseLsofFields', () {
    final conns = parseLsofFields(_lsof);

    test('keeps only sockets that have a peer', () {
      // 5 sockets with a peer; the two LISTEN sockets are dropped.
      expect(conns.length, 6);
      expect(conns.any((c) => c.state == 'LISTEN'), isFalse);
    });

    test('attaches the trailing TST= state to the right connection', () {
      final closeWait = conns.singleWhere((c) => c.remoteIp == '104.18.26.48');
      expect(closeWait.state, 'CLOSE_WAIT');
      final first = conns.first;
      expect(first.state, 'ESTABLISHED');
      expect(first.processName, 'Comet Helper');
      expect(first.pid, 100);
      expect(first.remotePort, 443);
    });

    test('parses bracketed IPv6 peers', () {
      final v6 = conns.singleWhere((c) => c.pid == 300);
      expect(v6.remoteIp, '2606:4700::6810:84e5');
      expect(v6.remotePort, 443);
    });

    test('unescapes lsof \\x20 sequences in command names', () {
      final parsed = parseLsofFields(
        'p1\nccom.apple.Web\\x20Content\nf1\nPTCP\nn1.1.1.1:1->2.2.2.2:2\nTST=ESTABLISHED\n',
      );
      expect(parsed.single.processName, 'com.apple.Web Content');
    });

    test('handles empty output', () {
      expect(parseLsofFields(''), isEmpty);
    });
  });

  group('parsePsOutput', () {
    test('keeps paths that contain spaces', () {
      final procs = parsePsOutput(_ps);
      expect(procs.length, 4);
      expect(procs[1].pid, 100);
      expect(procs[1].ppid, 200);
      expect(procs[1].path, contains('Comet Helper.app'));
    });
  });

  group('parseSsOutput', () {
    test('extracts peer, pid and process name', () {
      final conns = parseSsOutput(
        'ESTAB 0 0 10.0.0.2:44444 142.250.1.1:443 users:(("firefox",pid=123,fd=40))\n'
        'ESTAB 0 0 10.0.0.2:44445 [2a00:1450::1]:443 users:(("firefox",pid=123,fd=41))\n'
        'ESTAB 0 0 10.0.0.2:44446 1.1.1.1:443\n',
      );
      expect(conns.length, 2); // third has no owning process info
      expect(conns.first.processName, 'firefox');
      expect(conns.first.pid, 123);
      expect(conns.first.state, 'ESTABLISHED');
      expect(conns.last.remoteIp, '2a00:1450::1');
    });
  });

  group('windows parsers', () {
    test('accepts a list and a single bare object', () {
      final list = parseWindowsProcesses(
        '[{"ProcessId":4,"ParentProcessId":0,"Name":"System","ExecutablePath":null},'
        '{"ProcessId":9,"ParentProcessId":4,"Name":"chrome.exe","ExecutablePath":"C:\\\\Program Files\\\\Google\\\\chrome.exe"}]',
      );
      expect(list.length, 2);
      expect(list.last.path, endsWith('chrome.exe'));

      final single = parseWindowsConnections(
        '{"RemoteAddress":"8.8.8.8","RemotePort":443,"OwningProcess":9}',
        {9: 'chrome.exe'},
      );
      expect(single.single.remoteIp, '8.8.8.8');
      expect(single.single.processName, 'chrome.exe');
    });

    test('tolerates empty or invalid output', () {
      expect(parseWindowsProcesses(''), isEmpty);
      expect(parseWindowsConnections('not json', {}), isEmpty);
    });
  });

  group('appIdentity', () {
    test('merges macOS helper processes into the outer .app bundle', () {
      final main = appIdentity(
        '/Applications/Comet.app/Contents/MacOS/Comet',
        '',
      );
      final helper = appIdentity(
        '/Applications/Comet.app/Contents/Frameworks/X/Comet Helper.app/Contents/MacOS/Comet Helper',
        '',
      );
      expect(main.id, '/Applications/Comet.app');
      expect(helper.id, main.id);
      expect(helper.name, 'Comet');
    });

    test('falls back to executable name, stripping .exe', () {
      expect(appIdentity('C:\\Apps\\Chrome.EXE', '').name, 'Chrome');
      expect(appIdentity('C:\\Apps\\Chrome.EXE', '').id, 'chrome');
      expect(appIdentity('/Users/me/.local/bin/claude', '').name, 'claude');
      expect(appIdentity('', 'firefox').name, 'firefox');
      expect(appIdentity('', '').id, 'unknown');
    });
  });

  group('groupConnectionsByApp', () {
    final apps = groupConnectionsByApp(
      parseLsofFields(_lsof),
      parsePsOutput(_ps),
    );

    test('groups helper + main process under one app', () {
      final comet = apps.singleWhere((a) => a.name == 'Comet');
      expect(comet.pids, {100, 200});
    });

    test('drops loopback, non-established and listening sockets', () {
      final all = apps.expand((a) => a.connections);
      expect(all.any((c) => c.remoteIp == '127.0.0.1'), isFalse);
      expect(
        all.any((c) => c.remoteIp == '104.18.26.48'),
        isFalse,
      ); // CLOSE_WAIT
    });

    test('dedupes connections per remote IP', () {
      final comet = apps.singleWhere((a) => a.name == 'Comet');
      expect(comet.endpointCounts['172.64.146.215'], 2);
      expect(comet.endpointCounts.length, 2);
    });

    test('orders apps by endpoint count', () {
      expect(apps.first.name, 'Comet');
    });

    test('flags system processes', () {
      final sys = groupConnectionsByApp([
        const AppConnection(
          pid: 1,
          processName: 'launchd',
          protocol: 'TCP',
          state: 'ESTABLISHED',
          remoteIp: '8.8.8.8',
          remotePort: 443,
        ),
      ], parsePsOutput(_ps));
      expect(sys.single.isSystem, isTrue);
      expect(apps.any((a) => a.isSystem), isFalse);
    });
  });

  group('AppConnectionService.poll', () {
    test('macOS runs lsof + ps and groups the result', () async {
      final calls = <String>[];
      final service = AppConnectionService(
        platform: 'macos',
        runner: (exe, args) async {
          calls.add(exe);
          return exe == 'lsof' ? _lsof : _ps;
        },
      );
      final apps = await service.poll();
      expect(calls, containsAll(['lsof', 'ps']));
      expect(apps.map((a) => a.name), contains('Comet'));
    });

    test(
      'a failing command yields an empty list instead of throwing',
      () async {
        final service = AppConnectionService(
          platform: 'macos',
          runner: (_, _) async => '',
        );
        expect(await service.poll(), isEmpty);
      },
    );

    test('unsupported platforms return nothing', () async {
      final service = AppConnectionService(
        platform: 'ios',
        runner: (_, _) async => 'x',
      );
      expect(await service.poll(), isEmpty);
    });
  });
}
