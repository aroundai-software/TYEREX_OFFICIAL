// lib/screens/report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/user_provider.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:printing/printing.dart';
import '../widgets/printable_job_card.dart';
import '../theme/app_theme.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import '../providers/report_provider.dart';
import '../providers/admin_settings_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/local_media_service.dart';
import '../utils/date_utils.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../utils/file_download_helper.dart';

// Assuming DamagePainter is in a shared file or defined elsewhere.
// If not, you can copy the DamagePainter class from job_card_screen.dart to here.
class DamagePainter extends CustomPainter {
  final List<Offset> marks;
  DamagePainter({required this.marks});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // SCALE RELATIVE COORDINATES TO THE CANVAS SIZE
    for (final mark in marks) {
      final x = mark.dx * size.width;
      final y = mark.dy * size.height;
      canvas.drawCircle(Offset(x, y), 5.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DamagePainter oldDelegate) =>
      oldDelegate.marks != marks;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _filteredReports = [];

  final _vehicleNoController = TextEditingController();
  final _brandController = TextEditingController();
  final _fromDateController = TextEditingController();
  final _toDateController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // Audio player for voice notes
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;
  String? _currentlyPlayingAudioId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchReportsForCurrentUser();
    });
    
    // Load admin settings to ensure feature flags are available
    Provider.of<AdminSettingsProvider>(context, listen: false).loadSettings();
  }

  /// Fetch reports for the currently logged-in user
  void _fetchReportsForCurrentUser() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user != null) {
      final userId = user['id'] as int;
      debugPrint('🔄 ReportScreen: Fetching reports for userId: $userId');
      Provider.of<ReportProvider>(context, listen: false).refresh(userId);
    }
  }

  @override
  void dispose() {
    _vehicleNoController.dispose();
    _brandController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _applyFilters() {
    // Get the full list from the provider
    final reportProvider = Provider.of<ReportProvider>(context, listen: false);
    List<Map<String, dynamic>> filtered = List.from(reportProvider.reports);
    if (_vehicleNoController.text.isNotEmpty) {
      final searchTerm = _vehicleNoController.text.toUpperCase();
      filtered = filtered
          .where((report) =>
              report['vehicles']?['Vehicle Number']
                  ?.toString()
                  .toUpperCase()
                  .contains(searchTerm) ??
              false)
          .toList();
    }
    if (_brandController.text.isNotEmpty) {
      final searchTerm = _brandController.text.toLowerCase();
      filtered = filtered
          .where((report) =>
              report['vehicles']?['vehicle_models']?['brand']
                  ?.toString()
                  .toLowerCase()
                  .contains(searchTerm) ??
              false)
          .toList();
    }
    if (_fromDate != null) {
      filtered = filtered
          .where((report) =>
              !AppDateUtils.parseUtcToLocal(report['created_at']).isBefore(_fromDate!))
          .toList();
    }
    if (_toDate != null) {
      final endOfDay =
          DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
      filtered = filtered
          .where((report) =>
              !AppDateUtils.parseUtcToLocal(report['created_at']).isAfter(endOfDay))
          .toList();
    }
    setState(() => _filteredReports = filtered);
  }

  void _clearFilters() {
    setState(() {
      _vehicleNoController.clear();
      _brandController.clear();
      _fromDateController.clear();
      _toDateController.clear();
      _fromDate = null;
      _toDate = null;
      // Get the full list from the provider
      final reportProvider =
          Provider.of<ReportProvider>(context, listen: false);
      _filteredReports = reportProvider.reports;
    });
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          _fromDateController.text = DateFormat('dd-MM-yyyy').format(picked);
        } else {
          _toDate = picked;
          _toDateController.text = DateFormat('dd-MM-yyyy').format(picked);
        }
      });
      _applyFilters();
    }
  }

  bool _hasMarks(dynamic marksRaw) {
    if (marksRaw == null) return false;
    if (marksRaw is List) return marksRaw.isNotEmpty;
    if (marksRaw is Map) return marksRaw.isNotEmpty;
    if (marksRaw is String) {
      return marksRaw.isNotEmpty && marksRaw != '[]' && marksRaw != '{}';
    }
    return false;
  }

  bool _hasBarcode(dynamic barcodeRaw) {
    if (barcodeRaw == null) return false;
    if (barcodeRaw is Map) return barcodeRaw.isNotEmpty;
    if (barcodeRaw is String) {
      return barcodeRaw.isNotEmpty && barcodeRaw != '{}' && barcodeRaw != '[]';
    }
    return false;
  }

  String _formatJsonCell(dynamic raw) {
    if (raw == null) return 'N/A';
    if (raw is List) {
      if (raw.isEmpty) return 'N/A';
      return raw
          .map((item) => (item is Map ? item['text'] ?? item['name'] ?? item.toString() : item).toString())
          .join(', ');
    }
    if (raw is Map) {
      if (raw.isEmpty) return 'N/A';
      return raw.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    if (raw is String) {
      if (raw.isEmpty || raw == '[]' || raw == '{}') return 'N/A';
      try {
        final decoded = jsonDecode(raw);
        return _formatJsonCell(decoded);
      } catch (_) {
        return raw;
      }
    }
    return raw.toString();
  }

  Future<void> _downloadReport() async {
    if (_filteredReports.isEmpty) {
      _showErrorSnackBar('No reports to download.');
      return;
    }

    // 1. Define the CSV headers
    final List<String> headers = [
      'Date & Time',
      'Vehicle No',
      'Vehicle Name',
      'Brand',
      'Model',
      'Client Name',
      'Client Phone',
      'Odometer',
      'Status',
      'Complaints',
      'Executive'
    ];

    // 2. Create the list of rows, starting with the headers
    List<List<dynamic>> rows = [];
    rows.add(headers);

    // 3. Add data for each report
    for (final report in _filteredReports) {
      final vehicle = report['vehicles'];
      final model = vehicle?['vehicle_models'];
      rows.add([
        DateFormat('dd-MM-yyyy HH:mm')
            .format(AppDateUtils.parseUtcToLocal(report['created_at'])),
        vehicle?['Vehicle Number'] ?? 'N/A',
        vehicle?['vehicle_name'] ?? 'N/A',
        model?['brand'] ?? 'N/A',
        model?['Model name'] ?? 'N/A',
        report['Owner name'] ?? 'N/A',
        report['client_phone'] ?? 'N/A',
        report['odometer_reading']?.toString() ?? 'N/A',
        report['status'] ?? 'N/A',
        _formatJsonCell(
            report['complaint']), // Use your existing formatting function
        report['executive']?['username'] ?? 'N/A',
      ]);
    }

    // 4. Convert the list of lists into a CSV string
    final String csv = const ListToCsvConverter().convert(rows);

    // 5. Trigger the download for web
    final blob = html.Blob([csv]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download",
          "autofix_reports_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv")
      ..click();
    html.Url.revokeObjectUrl(url);

    _showSuccessSnackBar('Report downloaded successfully!');
  }

  Future<void> _openLocalMediaViewer(int jobId) async {
    final items = LocalMediaService().listByJob(jobId);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Local Media'),
          content: SizedBox(
            width: 600,
            height: 420,
            child: items.isEmpty
                ? const Center(child: Text('No local media for this job.'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isPhoto = item['type'] == 'photo';
                      final audioId = item['id'] as String;
                      final Uint8List bytes = item['bytes'] as Uint8List;
                      final isCurrentlyPlaying = _currentlyPlayingAudioId == audioId && _isPlayingAudio;
                      
                      return ListTile(
                        leading: isPhoto
                            ? Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover)
                            : Icon(
                                isCurrentlyPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                color: Colors.blueGrey,
                                size: 48,
                              ),
                        title: Text(item['fileName'] ?? audioId),
                        subtitle: Text('${item['mime'] ?? ''} • ${(bytes.length / 1024).toStringAsFixed(1)} KB'),
                        onTap: isPhoto 
                            ? () => _previewImage(bytes, item['fileName'] ?? 'image.jpg') 
                            : () => _playAudio(bytes, audioId),
                        trailing: Consumer<AdminSettingsProvider>(
                          builder: (context, adminSettings, _) {
                            if (!adminSettings.featureJobCardDownload) {
                              return const SizedBox.shrink();
                            }
                            return TextButton.icon(
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Download'),
                              onPressed: () => _saveOrShareBytes(bytes, item['fileName'] ?? 'media', mime: item['mime'] as String?),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            Consumer<AdminSettingsProvider>(
              builder: (context, adminSettings, _) {
                if (!adminSettings.featureJobCardDownload) {
                  return const SizedBox.shrink();
                }
                return TextButton(
                  onPressed: () => _exportZipForJob(jobId),
                  child: const Text('Export ZIP'),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveOrShareBytes(Uint8List bytes, String filename, {String? mime}) async {
    if (kIsWeb) {
      final blob = html.Blob([bytes], mime);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else if (FileDownloadHelper.isDesktop) {
      final path = await FileDownloadHelper.saveFileToDownloads(fileName: filename, bytes: bytes);
      FileDownloadHelper.openInFileManager(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads: $filename'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => FileDownloadHelper.openInFileManager(path),
            ),
          ),
        );
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = io.File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path, name: filename, mimeType: mime)]);
    }
  }

  Future<void> _exportZipForJob(int jobId) async {
    final zipBytes = LocalMediaService().exportZipForJob(jobId);
    final filename = 'job_${jobId}_media.zip';
    await _saveOrShareBytes(zipBytes, filename, mime: 'application/zip');
  }

  Future<void> _previewImage(Uint8List bytes, String name) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _playAudio(Uint8List bytes, String audioId) async {
    try {
      // Stop any currently playing audio
      if (_isPlayingAudio && _currentlyPlayingAudioId != audioId) {
        await _audioPlayer.stop();
      }

      if (_isPlayingAudio && _currentlyPlayingAudioId == audioId) {
        // Pause if this is the currently playing audio
        await _audioPlayer.pause();
        setState(() {
          _isPlayingAudio = false;
          _currentlyPlayingAudioId = null;
        });
      } else {
        // Play the audio
        if (kIsWeb) {
          // For web, create a blob URL
          final blob = html.Blob([bytes], 'audio/webm');
          final url = html.Url.createObjectUrlFromBlob(blob);
          await _audioPlayer.setSourceUrl(url);
          await _audioPlayer.resume();
        } else {
          // For mobile/desktop, save to temp file and play
          final tempDir = await getTemporaryDirectory();
          final tempFile = io.File('${tempDir.path}/temp_audio_$audioId.webm');
          await tempFile.writeAsBytes(bytes);
          await _audioPlayer.play(DeviceFileSource(tempFile.path));
        }

        setState(() {
          _isPlayingAudio = true;
          _currentlyPlayingAudioId = audioId;
        });

        // Listen for audio completion
        _audioPlayer.onPlayerComplete.listen((_) {
          setState(() {
            _isPlayingAudio = false;
            _currentlyPlayingAudioId = null;
          });
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to play audio: $e');
      setState(() {
        _isPlayingAudio = false;
        _currentlyPlayingAudioId = null;
      });
    }
  }

  Future<void> _printJobCard(Map<String, dynamic> reportData) async {
    try {
      // 1. Generate the PDF bytes using your existing function
      final pdfBytes = await generateJobCardPdf(reportData);

      // 2. Open the native print preview screen
      await Printing.layoutPdf(onLayout: (format) => pdfBytes);
    } catch (e) {
      _showErrorSnackBar('Could not generate PDF: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(milliseconds: 100),
        ));
  }

  void _showSuccessSnackBar(String message) {
    // Commented out to reduce UI noise
    // if (!mounted) return;
    // ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  bool _isCourierJob(Map<String, dynamic> report) {
    final vehicle = report['vehicles'];
    if (vehicle != null && vehicle['Vehicle Number'] == 'Courier Package') {
      return true;
    }
    final marks = report['marks'];
    if (marks is Map && marks['is_courier'] == true) {
      return true;
    } else if (marks is String && marks.isNotEmpty) {
      try {
        final decoded = jsonDecode(marks);
        if (decoded is Map && decoded['is_courier'] == true) return true;
      } catch (_) {}
    }
    return false;
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Ongoing':
        return Colors.orange;
      case 'Not Started':
        return Colors.red;
      default:
        return Colors.grey.shade600;
    }
  }

  void _showMarksDialog(dynamic marksRaw) {
    if (!_hasMarks(marksRaw)) {
      _showErrorSnackBar('No damage marks recorded.');
      return;
    }
    List<Offset> marks = [];
    try {
      dynamic decoded;
      if (marksRaw is List) {
        decoded = marksRaw;
      } else if (marksRaw is Map) {
        decoded = marksRaw['marks'] ?? marksRaw['points'] ?? [];
        if (decoded is! List) decoded = [];
      } else if (marksRaw is String) {
        decoded = jsonDecode(marksRaw);
      }
      if (decoded is List) {
        marks = decoded
            .map((m) =>
                Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()))
            .toList();
      }
    } catch (e) {
      _showErrorSnackBar('Could not display damage marks.');
      return;
    }
    if (marks.isEmpty) {
      _showErrorSnackBar('No damage marks recorded.');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: AspectRatio(
          aspectRatio: 0.8466666666666667,
          child: CustomPaint(
            foregroundPainter: DamagePainter(marks: marks),
            child: Image.asset(
              'assets/images/car_outline.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  void _showWarrantyDialog(dynamic barcodeRaw) {
    if (!_hasBarcode(barcodeRaw)) {
      _showErrorSnackBar('No warranty QR codes recorded.');
      return;
    }
    Map<String, dynamic> barcodeData = {};
    try {
      if (barcodeRaw is Map) {
        barcodeData = Map<String, dynamic>.from(barcodeRaw);
      } else if (barcodeRaw is String) {
        barcodeData = jsonDecode(barcodeRaw) as Map<String, dynamic>;
      }
    } catch (e) {
      _showErrorSnackBar('Could not parse warranty data.');
      return;
    }
    if (barcodeData.isEmpty) {
      _showErrorSnackBar('No warranty QR codes recorded.');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Warranty QRs'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: barcodeData.length,
            itemBuilder: (context, index) {
              String position = barcodeData.keys.elementAt(index);
              final val = barcodeData[position];
              Map<String, dynamic> details = val is Map ? Map<String, dynamic>.from(val) : {};
              String qr = details['qr']?.toString() ?? '';
              String spec = details['spec']?.toString() ?? '';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (spec.isNotEmpty)
                      Text('Spec: $spec', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    if (qr.isNotEmpty)
                      Center(
                        child: QrImageView(
                          data: qr,
                          version: QrVersions.auto,
                          size: 150.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _shareWarrantyPDF(Map<String, dynamic> report) async {
    final barcodeRaw = report['barcode'];
    if (!_hasBarcode(barcodeRaw)) {
      _showErrorSnackBar('No warranty QR codes recorded.');
      return;
    }

    Map<String, dynamic> barcodeData = {};
    try {
      if (barcodeRaw is Map) {
        barcodeData = Map<String, dynamic>.from(barcodeRaw);
      } else if (barcodeRaw is String) {
        barcodeData = jsonDecode(barcodeRaw) as Map<String, dynamic>;
      }
    } catch (e) {
      _showErrorSnackBar('Could not parse warranty data.');
      return;
    }

    final String jobIdStr = (report['job_card_id']?.toString().isNotEmpty == true) 
        ? report['job_card_id'].toString() 
        : report['id']?.toString() ?? 'N/A';
    final vehicle = report['vehicles'];
    final vehicleNo = vehicle?['Vehicle Number'] ?? 'N/A';
    final clientName = report['Owner name'] ?? 'N/A';
    final clientPhone = report['client_phone'] ?? 'N/A';
    final odo = (report['odometer_reading'] ?? vehicle?['Odometer Reading'] ?? '').toString().trim();

    Map<String, dynamic> rMarksMap = {};
    final rMarksRaw = report['marks'];
    if (rMarksRaw != null) {
      if (rMarksRaw is Map) {
        rMarksMap = Map<String, dynamic>.from(rMarksRaw);
      } else if (rMarksRaw is String) {
        try { rMarksMap = Map<String, dynamic>.from(jsonDecode(rMarksRaw)); } catch (_) {}
      }
    }
    final String rAddress = (rMarksMap['address'] ?? report['address'] ?? report['bookings']?['pickup_address'] ?? '').toString().trim();

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text('Tyre Warranty Details', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Job Card: $jobIdStr', style: const pw.TextStyle(fontSize: 16)),
              if (vehicleNo.isNotEmpty && vehicleNo != 'Courier Package' && vehicleNo != 'N/A') ...[
                pw.Text('Vehicle: $vehicleNo', style: const pw.TextStyle(fontSize: 16)),
                if (odo.isNotEmpty && odo != 'N/A')
                  pw.Text('Odometer Reading: $odo km', style: const pw.TextStyle(fontSize: 16)),
              ],
              pw.Text('Client: $clientName ($clientPhone)', style: const pw.TextStyle(fontSize: 16)),
              if (rAddress.isNotEmpty && rAddress != 'N/A')
                pw.Text('Address: $rAddress', style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 20),
              pw.Wrap(
                spacing: 20,
                runSpacing: 20,
                children: barcodeData.entries.map((entry) {
                  final position = entry.key;
                  final details = entry.value as Map<String, dynamic>;
                  final qr = details['qr']?.toString() ?? '';
                  final spec = details['spec']?.toString() ?? '';

                  return pw.Container(
                    width: 200,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(position, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 5),
                        if (spec.isNotEmpty) pw.Text('Spec: $spec', style: const pw.TextStyle(fontSize: 12)),
                        pw.SizedBox(height: 10),
                        if (qr.isNotEmpty)
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: qr,
                            width: 120,
                            height: 120,
                          ),
                        if (qr.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 8),
                            child: pw.Text(qr, style: const pw.TextStyle(fontSize: 8)),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      final filename = 'job_${jobIdStr}_warranty_qrs.pdf';

      if (FileDownloadHelper.isDesktop) {
        final path = await FileDownloadHelper.saveFileToDownloads(fileName: filename, bytes: bytes);
        FileDownloadHelper.openInFileManager(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to Downloads: $filename'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => FileDownloadHelper.openInFileManager(path),
              ),
            ),
          );
        }
      } else {
        final dir = await getTemporaryDirectory();
        final file = io.File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);

        final String message = 'Warranty details for Job $jobIdStr (Vehicle: $vehicleNo)';
        await Share.shareXFiles(
          [XFile(file.path)],
          text: message,
          subject: 'Warranty details for Job $jobIdStr',
        );
      }
    } catch (e) {
      _showErrorSnackBar('Error generating or sharing PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ReportProvider, AdminSettingsProvider>(
      builder: (context, reportProvider, adminSettings, child) {
        final bool hasActiveFilters = _fromDate != null ||
            _toDate != null ||
            _vehicleNoController.text.isNotEmpty ||
            _brandController.text.isNotEmpty;

        final reportsToDisplay =
            hasActiveFilters ? _filteredReports : reportProvider.reports;

        final bool isMobile = MediaQuery.of(context).size.width < 600;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text(
              'Reports',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: AppTheme.primaryColor,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryColor),
                onPressed: () async {
                  final user =
                      Provider.of<UserProvider>(context, listen: false).user;
                  if (user != null) {
                    await reportProvider.refresh(user['id'] as int);
                    if (mounted && hasActiveFilters) _applyFilters();
                  }
                },
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final user =
                  Provider.of<UserProvider>(context, listen: false).user;
              if (user != null) {
                await reportProvider.refresh(user['id'] as int);
                if (mounted && hasActiveFilters) _applyFilters();
              }
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  sliver: SliverToBoxAdapter(
                    child: _buildFilterCard(),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverToBoxAdapter(
                    child: _buildServiceHistoryHeader(
                      reportsCount: reportsToDisplay.length,
                      adminSettings: adminSettings,
                    ),
                  ),
                ),
                if (reportProvider.isLoading && reportsToDisplay.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (reportsToDisplay.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: Center(
                        child: Text(
                          'No reports found.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ),
                    ),
                  )
                else if (isMobile)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _buildMobileReportCard(
                            reportsToDisplay[index],
                            adminSettings,
                          );
                        },
                        childCount: reportsToDisplay.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverToBoxAdapter(
                      child: _buildDesktopDataTable(
                        reportsToDisplay,
                        adminSettings,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterCard() {
    final bool hasActiveFilters = _fromDate != null ||
        _toDate != null ||
        _vehicleNoController.text.isNotEmpty ||
        _brandController.text.isNotEmpty;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filter Reports',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (hasActiveFilters)
                InkWell(
                  onTap: _clearFilters,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.clear_all_rounded, size: 16, color: Colors.red),
                        SizedBox(width: 4),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fromDateController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'From',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    suffixIcon: Icon(Icons.calendar_today, size: 16),
                    suffixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  readOnly: true,
                  onTap: () => _selectDate(context, true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _toDateController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'To',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    suffixIcon: Icon(Icons.calendar_today, size: 16),
                    suffixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  readOnly: true,
                  onTap: () => _selectDate(context, false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vehicleNoController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Vehicle No',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _brandController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Brand',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (_) => _applyFilters(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceHistoryHeader({
    required int reportsCount,
    required AdminSettingsProvider adminSettings,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Service History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (reportsCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$reportsCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (adminSettings.featureJobCardDownload)
            ElevatedButton.icon(
              onPressed: _downloadReport,
              icon: const Icon(Icons.download, size: 16),
              label: const Text(
                'Download',
                style: TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileReportCard(Map<String, dynamic> report, AdminSettingsProvider adminSettings) {
    final vehicle = report['vehicles'];
    final model = vehicle?['vehicle_models'];
    final vehicleNo = vehicle?['Vehicle Number'] ?? 'N/A';
    final vehicleName = vehicle?['vehicle_name'] ?? '';
    final brand = model?['brand'] ?? '';
    final modelName = model?['Model name'] ?? '';
    final createdDate = AppDateUtils.parseUtcToLocal(report['created_at']?.toString());
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(createdDate);
    final isCourier = _isCourierJob(report);

    String vehicleSub = '';
    if (vehicleName.isNotEmpty && vehicleName != 'N/A') {
      vehicleSub = vehicleName;
    } else if (brand.isNotEmpty || modelName.isNotEmpty) {
      vehicleSub = '$brand $modelName'.trim();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showMobileReportDetails(report, adminSettings),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            report['job_card_id']?.toString() ?? 'Job #${report['id']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCourier) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.inventory_2_outlined, size: 12, color: Colors.purple),
                                SizedBox(width: 3),
                                Text(
                                  'Courier',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      report['status'] ?? 'N/A',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    backgroundColor: _getStatusColor(report['status']),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (vehicleNo.isNotEmpty && vehicleNo != 'N/A')
                Row(
                  children: [
                    const Icon(Icons.directions_car_outlined, size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(
                      vehicleNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (vehicleSub.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '($vehicleSub)',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Client: ${report['Owner name']?.toString() ?? 'N/A'}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formattedDate,
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDataTable(
    List<Map<String, dynamic>> reports,
    AdminSettingsProvider adminSettings,
  ) {
    List<DataColumn2> columns = [];
    if (adminSettings.featureJobCardDownload) {
      columns.add(const DataColumn2(label: Text('PRINT'), size: ColumnSize.S));
    }
    columns.addAll(const [
      DataColumn2(label: Text('Job ID'), size: ColumnSize.M),
      DataColumn2(label: Text('Vehicle No.'), size: ColumnSize.M),
      DataColumn2(label: Text('Vehicle Name'), size: ColumnSize.M),
      DataColumn2(label: Text('Model'), size: ColumnSize.M),
      DataColumn2(label: Text('Brand'), size: ColumnSize.M),
      DataColumn2(label: Text('Color'), size: ColumnSize.S),
      DataColumn2(label: Text('Engine No'), size: ColumnSize.L),
      DataColumn2(label: Text('Chassis No'), size: ColumnSize.L),
      DataColumn2(label: Text('Client Name'), size: ColumnSize.M),
      DataColumn2(label: Text('Client Phone'), size: ColumnSize.M),
      DataColumn2(label: Text('Odometer'), size: ColumnSize.S),
      DataColumn2(label: Text('Executive'), size: ColumnSize.M),
      DataColumn2(label: Text('Date & Time'), size: ColumnSize.L),
      DataColumn2(label: Text('Status'), size: ColumnSize.M),
      DataColumn2(label: Text('Duration'), size: ColumnSize.M),
      DataColumn2(label: Text('Complaint'), size: ColumnSize.L),
      DataColumn2(label: Text('Suggested'), size: ColumnSize.L),
      DataColumn2(label: Text('Approved'), size: ColumnSize.L),
      DataColumn2(label: Text('Feedback Text'), size: ColumnSize.L),
      DataColumn2(label: Text('Feedback Voice'), size: ColumnSize.S),
      DataColumn2(label: Text('Marks'), size: ColumnSize.S),
      DataColumn2(label: Text('Warranty'), size: ColumnSize.S),
      DataColumn2(label: Text('Media'), size: ColumnSize.S),
    ]);

    final rows = List<DataRow>.generate(reports.length, (index) {
      final report = reports[index];
      final vehicle = report['vehicles'];
      final model = vehicle?['vehicle_models'];
      final localDate = AppDateUtils.parseUtcToLocal(report['created_at'].toString());

      List<DataCell> cells = [];
      if (adminSettings.featureJobCardDownload) {
        cells.add(
          DataCell(
            IconButton(
              icon: const Icon(Icons.download, color: AppTheme.textSecondary),
              onPressed: () => _printJobCard(report),
            ),
          ),
        );
      }

      cells.addAll([
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(report['job_card_id']?.toString() ?? 'Job #${report['id']}'),
              if (_isCourierJob(report)) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: const Text(
                    'Courier',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple),
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(Text(vehicle?['Vehicle Number'] ?? 'N/A')),
        DataCell(Text(vehicle?['vehicle_name'] ?? 'N/A')),
        DataCell(Text(model?['Model name'] ?? 'N/A')),
        DataCell(Text(model?['brand'] ?? 'N/A')),
        DataCell(Text(vehicle?['Color'] ?? 'N/A')),
        DataCell(Text(vehicle?['Engine Number'] ?? 'N/A')),
        DataCell(Text(vehicle?['Chasis Number'] ?? 'N/A')),
        DataCell(Text(report['Owner name'] ?? 'N/A')),
        DataCell(Text(report['client_phone'] ?? 'N/A')),
        DataCell(Text(report['odometer_reading']?.toString() ?? 'N/A')),
        DataCell(Text(report['executive']?['username'] ?? 'N/A')),
        DataCell(Text(DateFormat('dd/MM/yy, HH:mm').format(localDate))),
        DataCell(Chip(
            label: Text(report['status'] ?? 'N/A', style: const TextStyle(color: Colors.white, fontSize: 11)),
            backgroundColor: _getStatusColor(report['status']),
            padding: const EdgeInsets.symmetric(horizontal: 4))),
        DataCell(Text(_formatDuration(report['started_at'], report['completed_at']))),
        DataCell(Text(_formatJsonCell(report['complaint']), overflow: TextOverflow.ellipsis)),
        DataCell(Text(_formatJsonCell(report['suggested']), overflow: TextOverflow.ellipsis)),
        DataCell(Text(_formatJsonCell(report['approved']), overflow: TextOverflow.ellipsis)),
        DataCell(Text(report['customer_feedback_text'] ?? 'N/A')),
        DataCell(report['customer_feedback_audio'] != null
            ? IconButton(
                icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                onPressed: () async => await launchUrl(Uri.parse(report['customer_feedback_audio'])))
            : const Text('N/A')),
        DataCell(
            _hasMarks(report['marks'])
                ? TextButton(
                    onPressed: () => _showMarksDialog(report['marks']),
                    child: const Text('View'))
                : const Text('N/A')),
        DataCell(
            _hasBarcode(report['barcode'])
                ? TextButton(
                    onPressed: () => _showWarrantyDialog(report['barcode']),
                    child: const Text('View QRs'))
                : const Text('N/A')),
        DataCell(
          TextButton(
            onPressed: () => _openLocalMediaViewer(report['id'] as int),
            child: const Text('View Local'),
          ),
        ),
      ]);

      return DataRow(
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (index.isEven) return Colors.grey.withValues(alpha: 0.05);
          return null;
        }),
        cells: cells,
      );
    });

    return SizedBox(
      height: (reports.length * 50 + 60).toDouble().clamp(300.0, 800.0),
      child: DataTable2(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: adminSettings.featureJobCardDownload ? 3000 : 2900,
        isHorizontalScrollBarVisible: true,
        fixedLeftColumns: adminSettings.featureJobCardDownload ? 2 : 1,
        columns: columns,
        rows: rows,
      ),
    );
  }

  String _formatDuration(String? start, String? end) {
    if (start == null) return 'N/A';
    final startTime = DateTime.tryParse(start);
    if (startTime == null) return 'N/A';

    final endTime = (end != null ? DateTime.tryParse(end) : null) ?? DateTime.now();
    final duration = endTime.difference(startTime);

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  void _showMobileReportDetails(Map<String, dynamic> report, AdminSettingsProvider adminSettings) {
    bool hasQr = false;
    try {
      final barcodeRaw = report['barcode'];
      Map<String, dynamic> barcodeData = {};
      if (barcodeRaw is Map) {
        barcodeData = Map<String, dynamic>.from(barcodeRaw);
      } else if (barcodeRaw is String && barcodeRaw.isNotEmpty && barcodeRaw != '{}') {
        barcodeData = jsonDecode(barcodeRaw) as Map<String, dynamic>;
      }
      hasQr = barcodeData.values.any((details) {
        if (details is Map) {
          return details['qr']?.toString().isNotEmpty == true || details['has_image']?.toString() == 'true';
        }
        return false;
      });
    } catch (_) {}

    final vehicle = report['vehicles'];
    final model = vehicle?['vehicle_models'];
    final localDate = AppDateUtils.parseUtcToLocal(report['created_at'].toString());
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(localDate);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: const Text('Report Details'),
              centerTitle: true,
              elevation: 0,
              actions: [
                if (hasQr)
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.blue),
                    onPressed: () => _shareWarrantyPDF(report),
                    tooltip: 'Share QRs',
                  ),
                if (adminSettings.featureJobCardDownload)
                  IconButton(
                    icon: const Icon(Icons.print, color: Colors.blue),
                    onPressed: () => _printJobCard(report),
                  ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          report['job_card_id']?.toString() ?? 'Job #${report['id']}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        if (_isCourierJob(report)) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.inventory_2_outlined, size: 14, color: Colors.purple),
                                SizedBox(width: 4),
                                Text(
                                  'Courier Job',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailSection(
                              title: 'Vehicle Information',
                              items: [
                                _DetailItem('Vehicle No.', vehicle?['Vehicle Number'] ?? 'N/A'),
                                _DetailItem('Brand', model?['brand'] ?? 'N/A'),
                                _DetailItem('Vehicle Name', vehicle?['vehicle_name'] ?? 'N/A'),
                                _DetailItem('Model', model?['Model name'] ?? 'N/A'),
                                _DetailItem('Color', vehicle?['Color'] ?? 'N/A'),
                                _DetailItem('Engine No', vehicle?['Engine Number'] ?? 'N/A'),
                                _DetailItem('Chassis No', vehicle?['Chasis Number'] ?? 'N/A'),
                                _DetailItem('Odometer', report['odometer_reading']?.toString() ?? 'N/A'),
                              ],
                            ),
                            _buildDetailSection(
                              title: 'Client Details',
                              items: [
                                _DetailItem('Client Name', report['Owner name'] ?? 'N/A'),
                                _DetailItem('Client Phone', report['client_phone'] ?? 'N/A'),
                              ],
                            ),
                            _buildDetailSection(
                              title: 'Job & Timing',
                              items: [
                                _DetailItem('Executive', report['executive']?['username'] ?? 'N/A'),
                                _DetailItem('Status', report['status'] ?? 'N/A', statusColor: _getStatusColor(report['status'])),
                                _DetailItem('Date & Time', formattedDate),
                                _DetailItem('Duration', _formatDuration(report['started_at'], report['completed_at'])),
                              ],
                            ),
                            _buildDetailSection(
                              title: 'Findings & Actions',
                              items: [
                                _DetailItem('Complaint', _formatJsonCell(report['complaint']), isFullWidth: true),
                                _DetailItem('Suggested', _formatJsonCell(report['suggested']), isFullWidth: true),
                                _DetailItem('Approved', _formatJsonCell(report['approved']), isFullWidth: true),
                                _DetailItem('Feedback Text', report['customer_feedback_text'] ?? 'N/A', isFullWidth: true),
                              ],
                            ),
                            if (report['customer_feedback_audio'] != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Row(
                                  children: [
                                    const Text('Feedback Voice: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                                    IconButton(
                                      icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 30),
                                      onPressed: () async => await launchUrl(Uri.parse(report['customer_feedback_audio'])),
                                    ),
                                  ],
                                ),
                              ),
                            if (_hasMarks(report['marks']))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: OutlinedButton.icon(
                                  onPressed: () => _showMarksDialog(report['marks']),
                                  icon: const Icon(Icons.edit_note),
                                  label: const Text('View Damage Marks'),
                                ),
                              ),
                            if (_hasBarcode(report['barcode']))
                              _buildWarrantyQRSection(report['barcode']),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: OutlinedButton.icon(
                                onPressed: () => _openLocalMediaViewer(report['id'] as int),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('View Local Media'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required List<_DetailItem> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16.0,
            runSpacing: 14.0,
            children: items.map((item) {
              return SizedBox(
                width: item.isFullWidth ? double.infinity : (MediaQuery.of(context).size.width - 52) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.statusColor != null)
                      Chip(
                        label: Text(item.value, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        backgroundColor: item.statusColor,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                    else
                      Text(
                        item.value,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFFF3F4F6)),
        ],
      ),
    );
  }

  Widget _buildWarrantyQRSection(dynamic barcodeRaw) {
    Map<String, dynamic> barcodeData = {};
    try {
      if (barcodeRaw is Map) {
        barcodeData = Map<String, dynamic>.from(barcodeRaw);
      } else if (barcodeRaw is String) {
        barcodeData = jsonDecode(barcodeRaw) as Map<String, dynamic>;
      }
    } catch (e) {
      return const SizedBox.shrink();
    }

    if (barcodeData.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Warranty QRs',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16.0,
            runSpacing: 16.0,
            children: barcodeData.entries.map((entry) {
              final position = entry.key;
              final details = entry.value as Map<String, dynamic>;
              final qr = details['qr']?.toString() ?? '';
              final spec = details['spec']?.toString() ?? '';

              return SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (spec.isNotEmpty)
                      Text(
                        spec,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (qr.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          color: Colors.white,
                        ),
                        child: QrImageView(
                          data: qr,
                          version: QrVersions.auto,
                          size: 130.0,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DetailItem {
  final String label;
  final String value;
  final Color? statusColor;
  final bool isFullWidth;

  _DetailItem(this.label, this.value, {this.statusColor, this.isFullWidth = false});
}
