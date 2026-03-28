import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xl;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF080B10);
  static const surface = Color(0xFF0E1318);
  static const surfaceElevated = Color(0xFF131920);
  static const surfaceBorder = Color(0xFF1C2530);
  static const surfaceBorderBright = Color(0xFF243040);

  static const blue = Color(0xFF00AAFF);
  static const blueDim = Color(0xFF0066AA);
  static const blueFaint = Color(0x1A00AAFF);
  static const blueGlow = Color(0x3300AAFF);

  static const green = Color(0xFF00E676);
  static const greenFaint = Color(0x1A00E676);

  static const red = Color(0xFFFF3355);
  static const redFaint = Color(0x1AFF3355);

  static const amber = Color(0xFFFFAA00);
  static const amberFaint = Color(0x1AFFAA00);

  static const textPrimary = Color(0xFFE8EDF5);
  static const textSecondary = Color(0xFF6B7A8D);
  static const textMuted = Color(0xFF3A4550);
  static const textCode = Color(0xFF7EC8E3);
}

class AppText {
  static const labelXs = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
    fontFamily: 'monospace',
  );
  static const labelSm = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
    color: AppColors.textSecondary,
    fontFamily: 'monospace',
  );
  static const mono = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
  );
  static const monoSm = TextStyle(
    fontSize: 11,
    fontFamily: 'monospace',
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
  );
}

void main() {
  runApp(const QRShieldTesterApp());
}

class QRShieldTesterApp extends StatelessWidget {
  const QRShieldTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QRShield',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.blue,
          secondary: AppColors.green,
          surface: AppColors.surface,
          error: AppColors.red,
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const MainShell(),
    );
  }
}

// ─── Data Model ────────────────────────────────────────────────────────────────
class ScanRecord {
  final String id;
  final DateTime timestamp;
  final String status;
  final String? decodedUrl;
  final double? fusionScore;
  final double? dlProbability;
  final double? mlProbability;
  final String? fusionMode;
  final String? note;
  final String? error;

  ScanRecord({
    required this.id,
    required this.timestamp,
    required this.status,
    this.decodedUrl,
    this.fusionScore,
    this.dlProbability,
    this.mlProbability,
    this.fusionMode,
    this.note,
    this.error,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    status: json['status'] as String? ?? 'UNKNOWN',
    decodedUrl: json['decoded_url'] as String?,
    fusionScore: (json['fusion_score'] as num?)?.toDouble(),
    dlProbability: (json['dl_probability'] as num?)?.toDouble(),
    mlProbability: (json['ml_probability'] as num?)?.toDouble(),
    fusionMode: json['fusion_mode'] as String?,
    note: json['note'] as String?,
    error: json['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'decoded_url': decodedUrl,
    'fusion_score': fusionScore,
    'dl_probability': dlProbability,
    'ml_probability': mlProbability,
    'fusion_mode': fusionMode,
    'note': note,
    'error': error,
  };
}

// ─── History Service ───────────────────────────────────────────────────────────
class HistoryService {
  static const _key = 'qr_scan_history';

  static Future<List<ScanRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final now = DateTime.now();
    final records =
        raw
            .map(
              (e) =>
                  ScanRecord.fromJson(json.decode(e) as Map<String, dynamic>),
            )
            .where((r) => now.difference(r.timestamp).inDays < 3)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _save(records, prefs);
    return records;
  }

  static Future<void> add(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    existing.insert(0, record);
    await _save(existing, prefs);
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await load();
    records.removeWhere((r) => r.id == id);
    await _save(records, prefs);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _save(
    List<ScanRecord> records,
    SharedPreferences prefs,
  ) async {
    await prefs.setStringList(
      _key,
      records.map((r) => json.encode(r.toJson())).toList(),
    );
  }
}

// ─── Export Service ────────────────────────────────────────────────────────────
class ExportService {
  static String _fmt(double? v) => v != null ? v.toStringAsFixed(4) : 'N/A';
  static String _fmtDate(DateTime dt) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  static Future<File> exportPdf(List<ScanRecord> records) async {
    final pdf = pw.Document();
    final dateHeader = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now());
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'QRShield Scan History',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Exported: $dateHeader',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (_) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.5),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey800,
                ),
                children:
                    [
                          'Timestamp',
                          'Status',
                          'URL',
                          'Fusion',
                          'DL Prob',
                          'ML Prob',
                        ]
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              ...records.asMap().entries.map((entry) {
                final r = entry.value;
                final isEven = entry.key % 2 == 0;
                PdfColor statusColor = PdfColors.orange;
                if (r.status == 'SAFE') statusColor = PdfColors.green700;
                if (r.status == 'MALICIOUS' || r.status == 'DISTORTED_QR') {
                  statusColor = PdfColors.red700;
                }
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isEven ? PdfColors.grey100 : PdfColors.white,
                  ),
                  children: [
                    _cell(_fmtDate(r.timestamp)),
                    _cell(r.status, color: statusColor),
                    _cell(r.decodedUrl ?? 'N/A'),
                    _cell(_fmt(r.fusionScore)),
                    _cell(_fmt(r.dlProbability)),
                    _cell(_fmt(r.mlProbability)),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/qrshield_history_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _cell(String text, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8, color: color ?? PdfColors.black),
    ),
  );

  static Future<File> exportExcel(List<ScanRecord> records) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Scan History'];
    final headers = [
      'ID',
      'Timestamp',
      'Status',
      'Decoded URL',
      'Fusion Score',
      'DL Probability',
      'ML Probability',
      'Fusion Mode',
      'Note',
      'Error',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E3A5F'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      );
    }
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final values = [
        r.id,
        _fmtDate(r.timestamp),
        r.status,
        r.decodedUrl ?? '',
        r.fusionScore?.toStringAsFixed(4) ?? '',
        r.dlProbability?.toStringAsFixed(4) ?? '',
        r.mlProbability?.toStringAsFixed(4) ?? '',
        r.fusionMode ?? '',
        r.note ?? '',
        r.error ?? '',
      ];
      for (var j = 0; j < values.length; j++) {
        sheet
            .cell(
              xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1),
            )
            .value = xl.TextCellValue(
          values[j],
        );
      }
    }
    for (var i = 0; i < headers.length; i++) sheet.setColumnWidth(i, 20);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/qrshield_history_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    final bytes = excel.encode();
    if (bytes != null) await file.writeAsBytes(bytes);
    return file;
  }
}

// ─── Shared Widgets ────────────────────────────────────────────────────────────

class _TacticalCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final Color? bgColor;

  const _TacticalCard({
    required this.child,
    this.accentColor = AppColors.blue,
    this.padding = const EdgeInsets.all(16),
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          Positioned(
            top: 0,
            left: 0,
            child: _Corner(color: accentColor, flip: false),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _Corner(color: accentColor, flip: true),
          ),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  final bool flip;
  const _Corner({required this.color, required this.flip});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: flip ? 3.14159 : 0,
      child: SizedBox(
        width: 14,
        height: 14,
        child: CustomPaint(painter: _CornerPainter(color: color)),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(0, size.height * 0.65), Offset.zero, paint);
    canvas.drawLine(Offset.zero, Offset(size.width * 0.65, 0), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

class _ScanDivider extends StatelessWidget {
  final Color color;
  const _ScanDivider({this.color = AppColors.blue});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color.withValues(alpha: 0.5),
            color,
            color.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSafe = status == 'SAFE';
    final isBad = status == 'MALICIOUS' || status == 'DISTORTED_QR';
    final color = isSafe
        ? AppColors.green
        : (isBad ? AppColors.red : AppColors.amber);
    final icon = isSafe
        ? Icons.verified_rounded
        : (isBad ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DataRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label.toUpperCase(),
              style: AppText.labelXs.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: AppText.mono.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Main Shell ────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final GlobalKey<HistoryScreenState> _historyKey =
      GlobalKey<HistoryScreenState>();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [const TestingScreen(), HistoryScreen(key: _historyKey)];
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    if (index == 1) _historyKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder, width: 1),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _navItem(0, Icons.qr_code_scanner_rounded, 'SCANNER'),
              Container(width: 1, height: 28, color: AppColors.surfaceBorder),
              _navItem(1, Icons.storage_rounded, 'HISTORY'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? AppColors.blueFaint : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isActive
                      ? AppColors.blue.withValues(alpha: 0.25)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: isActive ? AppColors.blue : AppColors.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: isActive ? AppColors.blue : AppColors.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: isActive ? 28 : 0,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(1),
                boxShadow: isActive
                    ? [
                        const BoxShadow(
                          color: AppColors.blueGlow,
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Testing Screen ────────────────────────────────────────────────────────────
class TestingScreen extends StatefulWidget {
  const TestingScreen({super.key});

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _urlController = TextEditingController(
    text: 'http://72.62.246.243/scan',
  );
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String _backendUrl = 'http://72.62.246.243/scan';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = null;
      });
      _analyzeImage();
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;
    setState(() {
      _isLoading = true;
      _result = null;
    });
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));
      request.files.add(
        await http.MultipartFile.fromPath('file', _image!.path),
      );
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        final resultData = json.decode(response.body) as Map<String, dynamic>;
        setState(() => _result = resultData);
        await HistoryService.add(
          ScanRecord(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            status: resultData['status'] as String? ?? 'UNKNOWN',
            decodedUrl: resultData['decoded_url'] as String?,
            fusionScore: (resultData['fusion_score'] as num?)?.toDouble(),
            dlProbability: (resultData['dl_probability'] as num?)?.toDouble(),
            mlProbability: (resultData['ml_probability'] as num?)?.toDouble(),
            fusionMode: resultData['fusion_mode'] as String?,
            note: resultData['note'] as String?,
          ),
        );
      } else {
        setState(
          () => _result = {
            'error': 'Server error: ${response.statusCode}',
            'body': response.body,
          },
        );
      }
    } catch (e) {
      setState(() => _result = {'error': 'Connection failed: $e'});
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final target = uri.hasScheme ? uri : Uri.parse('https://$url');
    if (await canLaunchUrl(target)) {
      await launchUrl(target, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildEndpointCard(),
                const SizedBox(height: 14),
                _buildDropZone(),
                const SizedBox(height: 14),
                _buildScanActions(),
                const SizedBox(height: 28),
                if (_isLoading) _buildLoader(),
                if (!_isLoading && _result != null) _buildResultCard(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.surface,
      expandedHeight: 68,
      pinned: true,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.blue,
                AppColors.blue,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 14),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.blueFaint,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: AppColors.blue.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: AppColors.blue,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'QR',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
            const Text(
              'SHIELD',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.5,
                color: AppColors.blue,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointCard() {
    return _TacticalCard(
      accentColor: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router_rounded, size: 11, color: AppColors.blue),
              const SizedBox(width: 6),
              Text(
                'BACKEND ENDPOINT',
                style: AppText.labelXs.copyWith(color: AppColors.blue),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
            onChanged: (val) => _backendUrl = val,
            style: AppText.mono.copyWith(
              color: AppColors.textCode,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: AppColors.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: AppColors.surfaceBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: AppColors.blue, width: 1),
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.link_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    final hasImage = _image != null;
    return _TacticalCard(
      accentColor: hasImage ? AppColors.blue : AppColors.surfaceBorderBright,
      padding: EdgeInsets.zero,
      bgColor: AppColors.surfaceElevated,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 230,
          width: double.infinity,
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(_image!, fit: BoxFit.cover),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.bg.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bg.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: AppColors.blue.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 11,
                              color: AppColors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'IMAGE LOADED',
                              style: AppText.labelXs.copyWith(
                                color: AppColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.surfaceBorderBright,
                        ),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        size: 30,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'NO IMAGE SELECTED',
                      style: AppText.labelSm.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'capture or import a QR code image',
                      style: AppText.monoSm.copyWith(fontSize: 10),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildScanActions() {
    return Row(
      children: [
        Expanded(
          child: _scanBtn(
            icon: Icons.camera_alt_rounded,
            label: 'CAMERA',
            onTap: () => _pickImage(ImageSource.camera),
            primary: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _scanBtn(
            icon: Icons.photo_library_rounded,
            label: 'GALLERY',
            onTap: () => _pickImage(ImageSource.gallery),
            primary: false,
          ),
        ),
      ],
    );
  }

  Widget _scanBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [Color(0xFF0077CC), Color(0xFF00AAFF)],
                )
              : null,
          color: primary ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: primary ? Colors.transparent : AppColors.surfaceBorderBright,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: primary ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: primary ? Colors.white : AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return _TacticalCard(
      accentColor: AppColors.blue,
      child: Column(
        children: [
          const SizedBox(height: 24),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: AppColors.blue,
              strokeWidth: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ANALYZING QR CODE',
            style: AppText.labelSm.copyWith(color: AppColors.blue),
          ),
          const SizedBox(height: 5),
          Text(
            'scanning for threat vectors…',
            style: AppText.monoSm.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final status = _result!['status'] as String? ?? 'UNKNOWN';
    final isSafe = status == 'SAFE';
    final isBad = status == 'MALICIOUS' || status == 'DISTORTED_QR';
    final accentColor = isSafe
        ? AppColors.green
        : (isBad ? AppColors.red : AppColors.amber);
    final url = _result!['decoded_url'] as String?;

    Color? bgTint;
    if (isBad) bgTint = AppColors.red.withValues(alpha: 0.05);
    if (isSafe) bgTint = AppColors.green.withValues(alpha: 0.04);

    return _TacticalCard(
      accentColor: accentColor,
      bgColor: bgTint ?? AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCAN RESULT',
                      style: AppText.labelXs.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusBadge(status: status),
                  ],
                ),
              ),
              if (_result!['fusion_score'] != null)
                _ScoreMeter(
                  score: (_result!['fusion_score'] as num).toDouble(),
                  color: accentColor,
                ),
            ],
          ),
          _ScanDivider(color: accentColor),
          // Metrics
          _DataRow(
            label: 'Fusion Score',
            value: _result!['fusion_score']?.toString() ?? 'N/A',
          ),
          _DataRow(
            label: 'DL Prob',
            value: _result!['dl_probability']?.toString() ?? 'N/A',
          ),
          _DataRow(
            label: 'ML Prob',
            value: _result!['ml_probability']?.toString() ?? 'N/A',
          ),
          _DataRow(label: 'Mode', value: _result!['fusion_mode'] ?? 'N/A'),
          if (_result!['note'] != null)
            _DataRow(label: 'Note', value: _result!['note']!),
          if (_result!['error'] != null)
            _DataRow(
              label: 'Error',
              value: _result!['error']!,
              valueColor: AppColors.red,
            ),
          // URL
          _ScanDivider(color: accentColor),
          if (url != null && url.isNotEmpty)
            _UrlBlock(url: url, onVisit: () => _launchUrl(url))
          else
            _DataRow(label: 'URL', value: 'Not decoded'),
        ],
      ),
    );
  }
}

// ─── Score Meter ───────────────────────────────────────────────────────────────
class _ScoreMeter extends StatelessWidget {
  final double score;
  final Color color;
  const _ScoreMeter({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        color: color.withValues(alpha: 0.07),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            score.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'monospace',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'SCORE',
            style: AppText.labelXs.copyWith(
              fontSize: 7,
              color: color.withValues(alpha: 0.6),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── URL Block ─────────────────────────────────────────────────────────────────
class _UrlBlock extends StatelessWidget {
  final String url;
  final VoidCallback onVisit;
  const _UrlBlock({required this.url, required this.onVisit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.link_rounded,
              size: 10,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'DECODED URL',
              style: AppText.labelXs.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Text(
            url,
            style: AppText.mono.copyWith(
              color: AppColors.textCode,
              fontSize: 11,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onVisit,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0077CC), Color(0xFF00AAFF)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.open_in_browser_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'VISIT LINK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'URL copied to clipboard',
                          style: AppText.mono.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.surfaceElevated,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                      side: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AppColors.surfaceBorderBright),
                ),
                child: const Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── History Screen ────────────────────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<ScanRecord> _records = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() => _load();

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final records = await HistoryService.load();
    if (mounted)
      setState(() {
        _records = records;
        _loading = false;
      });
  }

  Future<void> _delete(String id) async {
    await HistoryService.delete(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, size: 15, color: AppColors.red),
            const SizedBox(width: 8),
            Text(
              'CLEAR ALL RECORDS',
              style: AppText.labelSm.copyWith(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        content: Text(
          'All scan records will be permanently deleted. This cannot be undone.',
          style: AppText.mono.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: AppText.labelXs.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'DELETE ALL',
              style: AppText.labelXs.copyWith(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await HistoryService.clearAll();
      await _load();
    }
  }

  Future<void> _exportPdf() async {
    if (_records.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportPdf(_records);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'QRShield Scan History PDF',
        ),
      );
    } catch (e) {
      _showError('PDF export failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_records.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportExcel(_records);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'QRShield Scan History Excel',
        ),
      );
    } catch (e) {
      _showError('Excel export failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppText.mono.copyWith(fontSize: 12)),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final target = uri.hasScheme ? uri : Uri.parse('https://$url');
    if (await canLaunchUrl(target)) {
      await launchUrl(target, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.blue,
                  strokeWidth: 1.5,
                ),
              ),
            )
          else ...[
            if (_records.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildToolbar(),
                ),
              ),
            SliverToBoxAdapter(child: _buildStatsBanner()),
            if (_records.isEmpty)
              SliverFillRemaining(child: _buildEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildHistoryTile(_records[i]),
                    childCount: _records.length,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.surface,
      pinned: true,
      expandedHeight: 68,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Color(0xFF9D6FFF),
                Color(0xFF9D6FFF),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10),
            child: GestureDetector(
              onTap: _clearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.redFaint,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_sweep_rounded,
                      size: 12,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'CLEAR',
                      style: AppText.labelXs.copyWith(color: AppColors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 14),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0x1A9D6FFF),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0x559D6FFF)),
              ),
              child: const Icon(
                Icons.storage_rounded,
                color: Color(0xFF9D6FFF),
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'SCAN ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
            const Text(
              'LOG',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.5,
                color: Color(0xFF9D6FFF),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Expanded(
          child: _exportBtn(
            Icons.picture_as_pdf_rounded,
            'PDF',
            const Color(0xFFFF6B35),
            _exportPdf,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _exportBtn(
            Icons.table_chart_rounded,
            'EXCEL',
            const Color(0xFF00C853),
            _exportExcel,
          ),
        ),
      ],
    );
  }

  Widget _exportBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: _exporting ? null : onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _exporting
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: color,
                      strokeWidth: 1.5,
                    ),
                  )
                : Icon(icon, size: 13, color: color),
            const SizedBox(width: 7),
            Text(
              'EXPORT $label',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBanner() {
    final total = _records.length;
    final safe = _records.where((r) => r.status == 'SAFE').length;
    final threat = _records
        .where((r) => r.status == 'MALICIOUS' || r.status == 'DISTORTED_QR')
        .length;
    final unknown = total - safe - threat;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            _statBlock('$total', 'TOTAL', AppColors.blue),
            _vDivider(),
            _statBlock('$safe', 'SAFE', AppColors.green),
            _vDivider(),
            _statBlock('$threat', 'THREAT', AppColors.red),
            _vDivider(),
            _statBlock('$unknown', 'UNKN', AppColors.amber),
            const Spacer(),
            const Icon(
              Icons.schedule_rounded,
              size: 10,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              '3-day retention',
              style: AppText.monoSm.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBlock(String count, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
        Text(
          label,
          style: AppText.labelXs.copyWith(
            color: color.withValues(alpha: 0.6),
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    color: AppColors.surfaceBorder,
  );

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: const Icon(
              Icons.storage_rounded,
              size: 30,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'NO RECORDS FOUND',
            style: AppText.labelSm.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            'scan a QR code to populate this log',
            style: AppText.monoSm.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(ScanRecord r) {
    final isSafe = r.status == 'SAFE';
    final isBad = r.status == 'MALICIOUS' || r.status == 'DISTORTED_QR';
    final statusColor = isSafe
        ? AppColors.green
        : (isBad ? AppColors.red : AppColors.amber);
    final ageHours = DateTime.now().difference(r.timestamp).inHours;
    final ageLabel = ageHours < 1
        ? 'Just now'
        : ageHours < 24
        ? '${ageHours}h ago'
        : '${DateTime.now().difference(r.timestamp).inDays}d ago';
    final timeStr = DateFormat('dd MMM · HH:mm').format(r.timestamp);

    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.redFaint,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DELETE',
              style: AppText.labelXs.copyWith(color: AppColors.red),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.delete_rounded, color: AppColors.red, size: 16),
          ],
        ),
      ),
      onDismissed: (_) => _delete(r.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: statusColor.withValues(alpha: 0.22)),
        ),
        child: Stack(
          children: [
            // Left accent bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + timestamp row
                  Row(
                    children: [
                      _StatusBadge(status: r.status),
                      const Spacer(),
                      Text(
                        timeStr,
                        style: AppText.monoSm.copyWith(fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          ageLabel,
                          style: AppText.labelXs.copyWith(
                            fontSize: 9,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Score pills
                  if (r.fusionScore != null ||
                      r.dlProbability != null ||
                      r.mlProbability != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (r.fusionScore != null)
                          _scorePill('FSN', r.fusionScore!, statusColor),
                        if (r.dlProbability != null)
                          _scorePill('DL', r.dlProbability!, AppColors.blue),
                        if (r.mlProbability != null)
                          _scorePill(
                            'ML',
                            r.mlProbability!,
                            const Color(0xFF9D6FFF),
                          ),
                      ],
                    ),
                  ],
                  // URL row
                  if (r.decodedUrl != null && r.decodedUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            size: 11,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              r.decodedUrl!,
                              style: AppText.mono.copyWith(
                                color: AppColors.textCode,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Visit
                          GestureDetector(
                            onTap: () => _launchUrl(r.decodedUrl!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.blueFaint,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: AppColors.blue.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.open_in_browser_rounded,
                                    size: 11,
                                    color: AppColors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'VISIT',
                                    style: AppText.labelXs.copyWith(
                                      color: AppColors.blue,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Copy
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: r.decodedUrl!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 12,
                                        color: AppColors.green,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'URL copied',
                                        style: AppText.mono.copyWith(
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: AppColors.surfaceElevated,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(3),
                                    side: const BorderSide(
                                      color: AppColors.surfaceBorder,
                                    ),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceBorder,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scorePill(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppText.labelXs.copyWith(
              color: color.withValues(alpha: 0.65),
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
