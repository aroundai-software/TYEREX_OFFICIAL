// lib/screens/warranty/warranty_details_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import '../../widgets/app_cached_image.dart';

class WarrantyDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> job;
  final Map<String, dynamic> barcodeData;
  final List<String> capturedQrImages;

  const WarrantyDetailsScreen({
    super.key,
    required this.job,
    required this.barcodeData,
    required this.capturedQrImages,
  });

  String _getOdometer() {
    final odo = job['odometer_reading'] ?? 
                job['vehicles']?['odometer'] ?? 
                job['vehicles']?['km_driven'];
    if (odo == null || odo.toString().trim().isEmpty || odo == 0 || odo == '0') return '';
    final odoStr = odo.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (odoStr.isEmpty) return '$odo';
    try {
      final numVal = int.parse(odoStr);
      return '${NumberFormat('#,##,###').format(numVal)} KM';
    } catch (_) {
      return '$odo KM';
    }
  }

  Future<void> _downloadImages(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );
    
    // Give the UI thread a moment to actually render the dialog before blocking it
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final archive = Archive();
      final String vehicleNo = (job['vehicles']?['Vehicle Number']?.toString() ?? job['vehicle_id']?.toString() ?? 'unknown').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      final qrFutures = barcodeData.entries.map((entry) async {
        final position = entry.key;
        final details = entry.value as Map<String, dynamic>;
        final String qr = details['qr'] ?? '';
        
        if (qr.isNotEmpty) {
          try {
            final painter = QrPainter(
              data: qr,
              version: QrVersions.auto,
              gapless: false,
              color: const Color(0xFF000000),
              emptyColor: const Color(0xFFFFFFFF),
            );
            final byteData = await painter.toImageData(300);
            if (byteData != null) {
              final bytes = byteData.buffer.asUint8List();
              final name = position.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
              return ArchiveFile('${vehicleNo}_$name.png', bytes.length, bytes)..compress = false;
            }
          } catch (e) {
            debugPrint('Failed to generate QR image: $e');
          }
        }
        return null;
      });

      final photoFutures = capturedQrImages.asMap().entries.map((entry) async {
        final index = entry.key + 1;
        final url = entry.value;
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            String ext = 'jpg';
            if (url.toLowerCase().contains('.png')) ext = 'png';
            if (url.toLowerCase().contains('.jpeg')) ext = 'jpg';
            final bytes = response.bodyBytes;
            return ArchiveFile('${vehicleNo}_Photo_$index.$ext', bytes.length, bytes)..compress = false;
          }
        } catch (e) {
          debugPrint('Failed to load image for ZIP: $e');
        }
        return null;
      });

      // Run all generations concurrently
      final allResults = await Future.wait([
        ...qrFutures,
        ...photoFutures,
      ]);

      for (var file in allResults) {
        if (file != null) {
          archive.addFile(file);
        }
      }

      if (archive.files.isEmpty) {
        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QRs or images to download'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('Failed to encode ZIP file');
      }

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog before sharing
        
        if (kIsWeb) {
          final blob = html.Blob([zipData], 'application/zip');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', '${vehicleNo}_Photos.zip')
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          final xFile = XFile.fromData(
            Uint8List.fromList(zipData),
            name: '${vehicleNo}_Photos.zip',
            mimeType: 'application/zip',
          );
          await Share.shareXFiles([xFile], text: 'Warranty Photos for $vehicleNo');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate ZIP: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadQRs(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );
    
    // Give the UI thread a moment to actually render the dialog before blocking it
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final List<pw.Widget> qrWidgets = [];
      final List<String> qrNames = [];
      
      barcodeData.forEach((position, detailsRaw) {
        final details = detailsRaw as Map<String, dynamic>;
        final String qr = details['qr'] ?? '';
        final String spec = details['spec'] ?? '';
        
        if (qr.isNotEmpty) {
          qrWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.all(10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(position, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  if (spec.isNotEmpty)
                    pw.Text('Spec: $spec', style: const pw.TextStyle(color: PdfColors.grey, fontSize: 14)),
                  pw.SizedBox(height: 20),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qr,
                    width: 300,
                    height: 300,
                  ),
                ],
              ),
            ),
          );
          qrNames.add(position.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'));
        }
      });

      final photoFutures = capturedQrImages.map((url) async {
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            return response.bodyBytes;
          }
        } catch (e) {
          debugPrint('Failed to load image for PDF: $e');
        }
        return null;
      });

      final photoBytesList = await Future.wait(photoFutures);

      for (var bytes in photoBytesList) {
        if (bytes != null) {
          qrWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.all(10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('Captured Image', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  pw.SizedBox(height: 20),
                  pw.Image(
                    pw.MemoryImage(bytes),
                    width: 400,
                    height: 400,
                    fit: pw.BoxFit.contain,
                  ),
                ],
              ),
            ),
          );
          qrNames.add('Photo_${qrWidgets.length}');
        }
      }

      final String vehicleNo = (job['vehicles']?['Vehicle Number']?.toString() ?? job['vehicle_id']?.toString() ?? 'unknown').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      if (qrWidgets.isEmpty) {
        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QRs or images to download'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final archive = Archive();

      for (int i = 0; i < qrWidgets.length; i++) {
        // Yield to the UI to keep the progress indicator spinning
        await Future.delayed(const Duration(milliseconds: 10));
        
        final pdf = pw.Document();
        final widget = qrWidgets[i];
        
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    margin: const pw.EdgeInsets.only(bottom: 24),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Warranty Job #${job['id']} Details', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Client: ${job['Owner name'] ?? job['client_name'] ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                  pw.Text('Phone: ${job['client_phone'] ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                  pw.Text('Date: ${job['created_at']?.toString().split('T').first ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Vehicle: ${job['vehicles']?['Vehicle Number'] ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                  pw.Text('Brand: ${job['vehicles']?['vehicle_models']?['brand'] ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                  pw.Text('Model: ${job['vehicles']?['vehicle_models']?['Model name'] ?? 'Unknown'}', style: const pw.TextStyle(fontSize: 12)),
                                  if (_getOdometer().isNotEmpty)
                                    pw.Text('Odometer: ${_getOdometer()}', style: const pw.TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Center(child: widget),
                  ),
                ],
              );
            },
          ),
        );
        
        final pdfBytes = await pdf.save();
        final fileName = '${vehicleNo}_${qrNames[i]}.pdf';
        archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes)..compress = false);
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('Failed to encode ZIP file');
      }

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog before sharing
        
        if (kIsWeb) {
          final blob = html.Blob([zipData], 'application/zip');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', '$vehicleNo.zip')
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          final xFile = XFile.fromData(
            Uint8List.fromList(zipData),
            name: '$vehicleNo.zip',
            mimeType: 'application/zip',
          );
          await Share.shareXFiles([xFile], text: 'Warranty QRs for $vehicleNo');
        }
      }

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate ZIP: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobIdStr = job['job_card_id']?.toString() ?? 'Job #${job['id']}';
    
    final validQrEntries = barcodeData.entries.where((e) {
      if (e.value is! Map) return false;
      final details = e.value as Map;
      return (details['qr']?.toString() ?? '').isNotEmpty;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text('Warranty Details - $jobIdStr', style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined, color: Colors.teal),
            tooltip: 'Download Photos',
            onPressed: () => _downloadImages(context),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.blue),
            tooltip: 'Download PDF',
            onPressed: () => _downloadQRs(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVehicleCard(),
            const SizedBox(height: 32),
            if (validQrEntries.isNotEmpty) ...[
              _buildSectionHeader('Scanned QR Codes', Icons.qr_code_2),
              const SizedBox(height: 16),
              _buildQrGrid(validQrEntries),
              const SizedBox(height: 32),
            ],
            if (capturedQrImages.isNotEmpty) ...[
              _buildSectionHeader('Captured Images', Icons.camera_alt),
              const SizedBox(height: 16),
              _buildCapturedImagesGrid(),
              const SizedBox(height: 32),
            ],
            if (validQrEntries.isEmpty && capturedQrImages.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Column(
                    children: [
                      Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No QRs available', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'download_photos_btn',
            onPressed: () => _downloadImages(context),
            icon: const Icon(Icons.photo_library),
            label: const Text('Download Photos', style: TextStyle(fontWeight: FontWeight.bold)),
            elevation: 4,
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'download_pdf_btn',
            onPressed: () => _downloadQRs(context),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold)),
            elevation: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 24, color: const Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
        ),
      ],
    );
  }

  Widget _buildVehicleCard() {
    final brand = job['vehicles']?['vehicle_models']?['brand']?.toString() ?? 'Unknown Brand';
    final model = job['vehicles']?['vehicle_models']?['Model name']?.toString() ?? 'Unknown Model';
    final vehicleNo = job['vehicles']?['Vehicle Number']?.toString() ?? job['vehicle_id']?.toString() ?? 'Unknown No.';
    
    final clientName = job['Owner name']?.toString() ?? job['client_name']?.toString() ?? 'Unknown Client';
    final clientPhone = job['client_phone']?.toString() ?? 'Unknown Phone';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_car_filled, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleNo,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$brand $model',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_getOdometer().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.speed, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _getOdometer(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$clientName • $clientPhone',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrGrid(List<MapEntry<String, dynamic>> validEntries) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: validEntries.length,
      itemBuilder: (context, index) {
        final entry = validEntries[index];
        final String position = entry.key;
        final Map<String, dynamic> details = entry.value as Map<String, dynamic>;
        final String qr = details['qr'] ?? '';
        final String spec = details['spec'] ?? '';

        return _buildItemCard(
          title: position,
          subtitle: spec.isNotEmpty ? 'Spec: $spec' : null,
          child: QrImageView(
            data: qr,
            version: QrVersions.auto,
            size: 140.0,
            backgroundColor: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildCapturedImagesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: capturedQrImages.length,
      itemBuilder: (context, index) {
        final url = capturedQrImages[index];
        return _buildItemCard(
          title: 'Photo ${index + 1}',
          child: AppCachedImage(
            imageUrl: url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }

  Widget _buildItemCard({required String title, String? subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: Center(child: child)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
