import 'dart:convert';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const ContactCallExporterApp());
}

class ContactCallExporterApp extends StatelessWidget {
  const ContactCallExporterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مصدّر الأرقام',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16697A),
          secondary: const Color(0xFFC44536),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FA),
        useMaterial3: true,
      ),
      home: const ExportHomePage(),
    );
  }
}

class ExportHomePage extends StatefulWidget {
  const ExportHomePage({super.key});

  @override
  State<ExportHomePage> createState() => _ExportHomePageState();
}

class _ExportHomePageState extends State<ExportHomePage> {
  bool _isBusy = false;
  String _status = 'جاهز للاستخراج';
  File? _lastFile;
  ExportSummary? _lastSummary;

  Future<void> _exportContactsOnly() async {
    await _runExport('جار استخراج جهات الاتصال...', () async {
      final contacts = await _readContacts();
      final accounts = await _readAccounts();
      return _saveExport(
        contacts: contacts,
        accounts: accounts,
        callLogs: const [],
        kind: ExportKind.contacts,
      );
    });
  }

  Future<void> _exportCallsOnly() async {
    await _runExport('جار استخراج سجل المكالمات...', () async {
      final callLogs = await _readCallLogs();
      return _saveExport(
        contacts: const [],
        accounts: const [],
        callLogs: callLogs,
        kind: ExportKind.calls,
      );
    });
  }

  Future<void> _exportEverything() async {
    await _runExport('جار استخراج جهات الاتصال وسجل المكالمات...', () async {
      final contacts = await _readContacts();
      final accounts = await _readAccounts();
      final callLogs = await _readCallLogs();
      return _saveExport(
        contacts: contacts,
        accounts: accounts,
        callLogs: callLogs,
        kind: ExportKind.all,
      );
    });
  }

  Future<void> _runExport(
    String busyStatus,
    Future<ExportResult> Function() task,
  ) async {
    setState(() {
      _isBusy = true;
      _status = busyStatus;
    });

    try {
      final result = await task();
      if (!mounted) return;
      setState(() {
        _lastFile = result.file;
        _lastSummary = result.summary;
        _status = 'تم إنشاء الملف';
      });
    } on PlatformException catch (error) {
      _showFailure(error.message ?? error.code);
    } catch (error) {
      _showFailure(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<List<Contact>> _readContacts() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      throw StateError('لم يتم منح صلاحية قراءة جهات الاتصال.');
    }

    return FlutterContacts.getAll(properties: ContactProperties.allProperties);
  }

  Future<List<Account>> _readAccounts() async {
    try {
      return FlutterContacts.accounts.getAll();
    } on PlatformException {
      return const [];
    }
  }

  Future<List<CallLogEntry>> _readCallLogs() async {
    final entries = await CallLog.get();
    return entries.toList(growable: false);
  }

  Future<ExportResult> _saveExport({
    required List<Contact> contacts,
    required List<Account> accounts,
    required List<CallLogEntry> callLogs,
    required ExportKind kind,
  }) async {
    final now = DateTime.now();
    final timestamp = _timestampForFile(now);
    final fileName = '${kind.filePrefix}_$timestamp.json';
    final directory = await getApplicationDocumentsDirectory();
    final exportsDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}exports',
    );
    await exportsDirectory.create(recursive: true);

    final file = File(
      '${exportsDirectory.path}${Platform.pathSeparator}$fileName',
    );
    final payload = <String, dynamic>{
      'generatedAt': now.toIso8601String(),
      'exportKind': kind.name,
      'networkUpload': false,
      'summary': {
        'contacts': contacts.length,
        'accounts': accounts.length,
        'callLogs': callLogs.length,
      },
      'accounts': accounts.map((account) => account.toJson()).toList(),
      'contactsNameNumberIndex': contacts.map(_contactNameNumberIndex).toList(),
      'contacts': contacts.map((contact) => contact.toJson()).toList(),
      'callLogs': callLogs.map(_callLogToJson).toList(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload), flush: true);

    return ExportResult(
      file: file,
      summary: ExportSummary(
        contactCount: contacts.length,
        accountCount: accounts.length,
        callLogCount: callLogs.length,
        generatedAt: now,
      ),
    );
  }

  Map<String, dynamic> _contactNameNumberIndex(Contact contact) {
    return {
      'id': contact.id,
      'displayName': contact.displayName,
      'name': contact.name?.toJson(),
      'phones': contact.phones.map((phone) => phone.toJson()).toList(),
      'accounts':
          contact.metadata?.accounts
              .map((account) => account.toJson())
              .toList() ??
          const [],
      'rawContacts':
          contact.android?.identifiers?.rawContacts
              .map((rawContact) => rawContact.toJson())
              .toList() ??
          const [],
    };
  }

  Map<String, dynamic> _callLogToJson(CallLogEntry entry) {
    final timestamp = entry.timestamp;
    final callDate = timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String();

    return {
      'id': entry.id,
      'name': entry.name,
      'number': entry.number,
      'formattedNumber': entry.formattedNumber,
      'callType': entry.callType?.name,
      'durationSeconds': entry.duration,
      'timestamp': timestamp,
      'dateTime': callDate,
      'cachedNumberType': entry.cachedNumberType,
      'cachedNumberLabel': entry.cachedNumberLabel,
      'cachedMatchedNumber': entry.cachedMatchedNumber,
      'simDisplayName': entry.simDisplayName,
      'phoneAccountId': entry.phoneAccountId,
    };
  }

  Future<void> _shareLastFile() async {
    final file = _lastFile;
    if (file == null) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        fileNameOverrides: [file.uri.pathSegments.last],
        subject: 'تصدير جهات الاتصال وسجل المكالمات',
        text: 'ملف التصدير موجود في المرفقات.',
      ),
    );
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _status = 'تعذر الاستخراج';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'الإعدادات',
          onPressed: FlutterContacts.permissions.openSettings,
        ),
      ),
    );
  }

  String _timestampForFile(DateTime value) {
    return value.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مصدّر الأرقام'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(
              status: _status,
              isBusy: _isBusy,
              summary: _lastSummary,
              filePath: _lastFile?.path,
            ),
            const SizedBox(height: 16),
            _ActionButton(
              icon: Icons.contacts_outlined,
              label: 'استخراج جهات الاتصال',
              onPressed: _isBusy ? null : _exportContactsOnly,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.call_outlined,
              label: 'استخراج سجل المكالمات',
              onPressed: _isBusy ? null : _exportCallsOnly,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.archive_outlined,
              label: 'استخراج الكل',
              isPrimary: true,
              onPressed: _isBusy ? null : _exportEverything,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _lastFile == null || _isBusy ? null : _shareLastFile,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('مشاركة آخر ملف'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.isBusy,
    required this.summary,
    required this.filePath,
  });

  final String status;
  final bool isBusy;
  final ExportSummary? summary;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isBusy ? Icons.sync_outlined : Icons.check_circle_outline,
                  color: isBusy ? colorScheme.secondary : colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (isBusy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (summary != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryChip(
                    icon: Icons.contacts_outlined,
                    label: '${summary!.contactCount} جهة',
                  ),
                  _SummaryChip(
                    icon: Icons.account_circle_outlined,
                    label: '${summary!.accountCount} حساب',
                  ),
                  _SummaryChip(
                    icon: Icons.call_outlined,
                    label: '${summary!.callLogCount} مكالمة',
                  ),
                ],
              ),
            ],
            if (filePath != null) ...[
              const SizedBox(height: 14),
              SelectableText(
                filePath!,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final style = isPrimary
        ? ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(54))
        : FilledButton.styleFrom(minimumSize: const Size.fromHeight(54));

    return isPrimary
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          )
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          );
  }
}

class ExportResult {
  const ExportResult({required this.file, required this.summary});

  final File file;
  final ExportSummary summary;
}

class ExportSummary {
  const ExportSummary({
    required this.contactCount,
    required this.accountCount,
    required this.callLogCount,
    required this.generatedAt,
  });

  final int contactCount;
  final int accountCount;
  final int callLogCount;
  final DateTime generatedAt;
}

enum ExportKind {
  contacts('contacts'),
  calls('calls'),
  all('contacts_calls');

  const ExportKind(this.filePrefix);

  final String filePrefix;
}
