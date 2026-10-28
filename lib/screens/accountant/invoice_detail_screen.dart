// lib/screens/accountant/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../utils/date_utils.dart';
import 'payment_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  final bool isPending;

  const InvoiceDetailScreen({super.key, required this.job, required this.isPending});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isCourier = false;

  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _suggestions = [];
  double _labourCost = 0;
  double _subtotal = 0;

  // ── Adjustments ──
  bool _gstEnabled = false;
  double _gstPercent = 18;

  String _discountType = 'flat';
  double _discountValue = 0;

  String _extraLabel = '';
  double _extraChargeAmount = 0;

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final parsed = AppDateUtils.parseUtcToLocal(dateStr);
      return DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
    } catch (_) {
      return 'Invalid Date';
    }
  }

  // ── Computed totals ──
  double get _discountAmount {
    if (_discountType == 'percent') {
      return (_subtotal + _labourCost) * (_discountValue / 100);
    }
    return _discountValue;
  }

  double get _gstAmount {
    if (!_gstEnabled) return 0;
    final base = (_subtotal + _labourCost) - _discountAmount + _extraChargeAmount;
    return base * (_gstPercent / 100);
  }

  double get _grandTotal {
    return (_subtotal + _labourCost) - _discountAmount + _extraChargeAmount + _gstAmount;
  }

  bool get _isJobBilled {
    final isConv = widget.job['is_converted'];
    if (isConv == true || isConv == 'true' || isConv == 1 || isConv == '1') return true;
    final bStatus = (widget.job['billing_status'] ?? '').toString().toLowerCase();
    if (bStatus == 'billed' || bStatus == 'paid' || bStatus == 'completed') return true;
    if (widget.job['payment_method'] != null && widget.job['payment_method'].toString().trim().isNotEmpty) return true;
    if (widget.job['paid_at'] != null && widget.job['paid_at'].toString().isNotEmpty) return true;
    return widget.job['billed_at'] != null && widget.job['billed_at'].toString().isNotEmpty;
  }

  bool get _isConvertedInTally {
    final isConv = widget.job['is_converted'];
    return isConv == true || isConv == 'true' || isConv == 1 || isConv == '1';
  }

  @override
  void initState() {
    super.initState();
    _parseJobData();
  }

  void _parseJobData() {
    final job = widget.job;
    _labourCost = ((job['labour_cost'] ?? 0) as num).toDouble();

    final rawComplaints = job['complaint'];
    if (rawComplaints is List) {
      _complaints = rawComplaints.map((e) => Map<String, dynamic>.from(e)).toList();
    } else if (rawComplaints is String) {
      try {
        final decoded = jsonDecode(rawComplaints) as List;
        _complaints = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final rawSuggested = job['suggested'];
    if (rawSuggested is List) {
      _suggestions = rawSuggested
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['type'] != AppConstants.typeComplaint)
          .toList();
    } else if (rawSuggested is String) {
      try {
        final decoded = jsonDecode(rawSuggested) as List;
        _suggestions = decoded
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['type'] != AppConstants.typeComplaint)
            .toList();
      } catch (_) {}
    }

    final marksObj = job['marks'];
    if (marksObj != null) {
      Map<String, dynamic>? marksMap;
      if (marksObj is String) {
        try {
          final decoded = jsonDecode(marksObj);
          if (decoded is Map<String, dynamic>) marksMap = decoded;
        } catch (_) {}
      } else if (marksObj is Map) {
        marksMap = Map<String, dynamic>.from(marksObj);
      }
      
      if (marksMap != null && marksMap['is_courier'] == true) {
        _isCourier = true;
        
        bool hasSavedDraft = false;
        if (_complaints.isNotEmpty) {
          for (final c in _complaints) {
            if (((c['amount'] ?? 0) as num) > 0 || ((c['unit_price'] ?? 0) as num) > 0) {
              hasSavedDraft = true;
              break;
            }
          }
        }

        if (!hasSavedDraft) {
          final products = marksMap['products'] as List<dynamic>?;
          if (products != null && products.isNotEmpty) {
            _complaints = products.map((p) {
              final name = (p['name'] as String?)?.isNotEmpty == true
                  ? p['name']
                  : '${p['brand'] ?? ''} ${p['model'] ?? ''} ${p['size'] ?? ''}'.trim();
              final qty = (p['qty'] ?? 1) as num;
              final unitPrice = ((p['price'] ?? p['amount'] ?? 0) as num).toDouble();
              final totalPrice = unitPrice * qty;
              final labelText = name.isNotEmpty ? name : 'Courier Package';
              return {
                'name': labelText,
                'text': labelText,
                'qty': qty.toInt(),
                'unit_price': unitPrice,
                'amount': totalPrice,
              };
            }).toList();
          } else {
            _complaints = [{'name': 'Courier Package', 'text': 'Courier Package', 'qty': 1, 'unit_price': 0.0, 'amount': 0.0}];
          }
        }
      }
    }

    _recalcTotals();

    // Restore adjustments
    if (job['gst_percent'] != null) {
      _gstEnabled = true;
      _gstPercent = (job['gst_percent'] as num).toDouble();
    }
    if (job['discount_amount'] != null) {
      _discountValue = (job['discount_amount'] as num).toDouble();
      _discountType = job['discount_type'] ?? 'flat';
    }
    if (job['extra_charge_amount'] != null) {
      _extraChargeAmount = (job['extra_charge_amount'] as num).toDouble();
      _extraLabel = job['extra_charge_label'] ?? 'Extra Charges';
    }
  }

  void _recalcTotals() {
    double itemTotal = 0;
    for (final c in _complaints) {
      itemTotal += ((c['amount'] ?? 0) as num).toDouble();
    }
    for (final s in _suggestions) {
      itemTotal += ((s['amount'] ?? 0) as num).toDouble();
    }
    _subtotal = itemTotal;
  }

  String _getCustomerName() {
    final bookingName = widget.job['bookings']?['customer_name']?.toString().trim();
    if (bookingName != null && bookingName.isNotEmpty) return bookingName;

    final reportOwner = widget.job['Owner name']?.toString().trim();
    if (reportOwner != null && reportOwner.isNotEmpty) return reportOwner;

    final vehicleOwner = widget.job['vehicles']?['Owner name']?.toString().trim();
    if (vehicleOwner != null && vehicleOwner.isNotEmpty) return vehicleOwner;

    return 'Walk-in Customer';
  }

  String _getCustomerPhone() {
    final bookingPhone = widget.job['bookings']?['customer_phone']?.toString().trim();
    if (bookingPhone != null && bookingPhone.isNotEmpty) return bookingPhone;

    final reportPhone = widget.job['client_phone']?.toString().trim();
    if (reportPhone != null && reportPhone.isNotEmpty) return reportPhone;

    final vehiclePhone = widget.job['vehicles']?['MobileNumber']?.toString().trim();
    if (vehiclePhone != null && vehiclePhone.isNotEmpty) return vehiclePhone;

    return '-';
  }
  String _getVehicleNo() => widget.job['vehicles']?['Vehicle Number'] ?? '-';
  String _getBrandModel() {
    final brand = widget.job['vehicles']?['vehicle_models']?['brand'] ?? '';
    final model = widget.job['vehicles']?['vehicle_models']?['Model name'] ?? '';
    return '$brand $model'.trim();
  }

  String _getOdometer() {
    final odo = widget.job['odometer_reading'] ?? 
                widget.job['vehicles']?['odometer'] ?? 
                widget.job['vehicles']?['km_driven'];
    if (odo == null || odo.toString().trim().isEmpty || odo == 0 || odo == '0') return 'N/A';
    final odoStr = odo.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (odoStr.isEmpty) return '$odo';
    try {
      final numVal = int.parse(odoStr);
      return '${NumberFormat('#,##,###').format(numVal)} KM';
    } catch (_) {
      return '$odo KM';
    }
  }

  Future<pw.Document> _generatePdf() async {
    final doc = pw.Document();
    final currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

    final jobCardId = widget.job['job_card_id'] ?? 'Job #${widget.job['id']}';
    final customerName = _getCustomerName();
    final customerPhone = _getCustomerPhone();
    final vehicleNo = _getVehicleNo();
    final model = _getBrandModel();
    final now = DateFormat('dd-MM-yyyy').format(DateTime.now());

    pw.MemoryImage? logoImage;
    try {
      final bytes = await DefaultAssetBundle.of(context).load('assets/images/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    doc.addPage(  
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      height: 60,
                      child: pw.Image(logoImage),
                    )
                  else
                    pw.Text('TYREX', style: pw.TextStyle(color: PdfColors.blue700, fontSize: 28, fontWeight: pw.FontWeight.bold)),
                  
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('JOB CARD / INVOICE', style: pw.TextStyle(color: PdfColors.blue700, fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(jobCardId, style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                      pw.Text('Generated: $now', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BILL TO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text(customerName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(customerPhone, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('VEHICLE DETAILS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text(vehicleNo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(model, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                        if (_getOdometer() != 'N/A')
                          pw.Text('KM: ${_getOdometer()}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                  pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 8),
              ..._complaints.map((c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text(c['text'] ?? c['name'] ?? '-', style: const pw.TextStyle(fontSize: 12))),
                    pw.Text(currency.format((c['amount'] ?? 0) as num), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              )),
              ..._suggestions.map((s) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text(s['text'] ?? s['name'] ?? '-', style: const pw.TextStyle(fontSize: 12))),
                    pw.Text(currency.format((s['amount'] ?? 0) as num), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              )),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Expanded(child: pw.Text(_isCourier ? 'Packages Subtotal' : 'Services & Parts Subtotal', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700))),
                pw.Text(currency.format(_subtotal), style: const pw.TextStyle(fontSize: 12)),
              ]),
              if (_isCourier || _labourCost > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text(_isCourier ? 'Delivery Charges' : 'Labour Charges', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700))),
                  pw.Text(currency.format(_labourCost), style: const pw.TextStyle(fontSize: 12)),
                ]),
              ],
              if (_discountAmount > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text('Discount', style: const pw.TextStyle(fontSize: 12, color: PdfColors.red))),
                  pw.Text('- ${currency.format(_discountAmount)}', style: const pw.TextStyle(fontSize: 12, color: PdfColors.red)),
                ]),
              ],
              if (_extraChargeAmount > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text(_extraLabel.isNotEmpty ? _extraLabel : 'Extra Charges', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700))),
                  pw.Text(currency.format(_extraChargeAmount), style: const pw.TextStyle(fontSize: 12)),
                ]),
              ],
              if (_gstEnabled && _gstAmount > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text('GST (${_gstPercent.toStringAsFixed(0)}%)', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700))),
                  pw.Text(currency.format(_gstAmount), style: const pw.TextStyle(fontSize: 12)),
                ]),
              ],
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('GRAND TOTAL', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
                  pw.Text(currency.format(_grandTotal), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc;
  }

  Future<void> _printInvoice() async {
    final doc = await _generatePdf();
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  Future<void> _shareInvoice() async {
    final doc = await _generatePdf();
    final bytes = await doc.save();
    final filename = 'invoice_${widget.job['job_card_id'] ?? widget.job['id']}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  Future<void> _showRequestEditDialog() async {
    if (_isJobBilled || _isConvertedInTally) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot request edit for job cards that are already billed or converted.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    bool isSubmitting = false;
    final jobCardId = widget.job['job_card_id'] ?? '#${widget.job['id']}';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Icon(Icons.edit_note, color: Color(0xFFD97706), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Request Edit',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send job card $jobCardId to executive so they can edit services, tyres, labour, or complaints.',
                      style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Reason for Edit Request (Optional):',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      enabled: !isSubmitting,
                      decoration: InputDecoration(
                        hintText: 'e.g., Wrong tyre added, update labour cost...',
                        hintStyle: const TextStyle(fontSize: 12.5, color: Colors.grey),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            final reportId = widget.job['id'];

                            // Prepare marks payload with reason
                            Map<String, dynamic> marksMap = {};
                            final rawMarks = widget.job['marks'];
                            if (rawMarks is Map) {
                              marksMap = Map<String, dynamic>.from(rawMarks);
                            } else if (rawMarks is String && rawMarks.isNotEmpty) {
                              try {
                                final decoded = jsonDecode(rawMarks);
                                if (decoded is Map<String, dynamic>) marksMap = decoded;
                              } catch (_) {}
                            }

                            final reason = reasonController.text.trim();
                            if (reason.isNotEmpty) {
                              marksMap['edit_request_reason'] = reason;
                              marksMap['edit_requested_at'] = DateTime.now().toUtc().toIso8601String();
                            }

                            final updateData = <String, dynamic>{
                              'status': AppConstants.statusEditRequested,
                              if (marksMap.isNotEmpty) 'marks': marksMap,
                            };

                            await supabase.from('reports').update(updateData).eq('id', reportId);

                            // Update local state
                            setState(() {
                              widget.job['status'] = AppConstants.statusEditRequested;
                              if (marksMap.isNotEmpty) widget.job['marks'] = marksMap;
                            });

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx, true);
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to request edit: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Edit request sent to executive successfully.')),
            ],
          ),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final isBilled = _isJobBilled;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.job['job_card_id'] ?? 'Job #${widget.job['id']}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isCourier) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Text(
                  'Courier',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _shareInvoice,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print / Download',
            onPressed: _printInvoice,
          ),
          if (!isBilled && !_isConvertedInTally)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              onSelected: (val) {
                if (val == 'request_edit') {
                  _showRequestEditDialog();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'request_edit',
                  enabled: widget.job['status'] != AppConstants.statusEditRequested,
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        color: widget.job['status'] == AppConstants.statusEditRequested
                            ? Colors.grey
                            : const Color(0xFFD97706),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.job['status'] == AppConstants.statusEditRequested
                            ? 'Edit Already Requested'
                            : 'Request Edit from Executive',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.job['status'] == AppConstants.statusEditRequested
                              ? Colors.grey
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header Banner
            Builder(
              builder: (context) {
                final bool isEditRequested = widget.job['status'] == AppConstants.statusEditRequested;
                if (isEditRequested) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFB923C), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note_rounded, color: Color(0xFFEA580C), size: 24),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EDIT REQUESTED TO EXECUTIVE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF9A3412),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Job card is currently with executive for editing services, tyres, or labour.',
                                style: TextStyle(fontSize: 12, color: Color(0xFFC2410C)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isBilled ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isBilled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBilled ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                        color: isBilled ? const Color(0xFF059669) : const Color(0xFFD97706),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConvertedInTally
                                  ? 'CONVERTED IN TALLY'
                                  : (isBilled ? 'MARKED AS BILLED FROM APP' : 'PENDING BILLING'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isBilled ? const Color(0xFF065F46) : const Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isConvertedInTally
                                  ? (widget.job['billed_at'] != null 
                                      ? 'Converted to Sales Invoice on ${_formatDate(widget.job['billed_at'])}' 
                                      : 'Converted to Sales Invoice in Tally')
                                  : (isBilled
                                      ? 'Payment reference recorded in App (for reference)'
                                      : 'Order created in Tally. Ready to be converted to Sales Invoice.'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isBilled ? const Color(0xFF047857) : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Customer & Vehicle
            _buildSection(
              icon: _isCourier ? Icons.local_shipping_outlined : Icons.person_outline,
              title: _isCourier ? 'Customer & Delivery Info' : 'Customer & Vehicle Details',
              color: const Color(0xFF2563EB),
              child: Column(
                children: [
                  _infoRow('Customer', _getCustomerName()),
                  _infoRow('Phone', _getCustomerPhone()),
                  if (!_isCourier) _infoRow('Vehicle No.', _getVehicleNo()),
                  if (!_isCourier) _infoRow('Model', _getBrandModel()),
                  if (!_isCourier && _getOdometer() != 'N/A') _infoRow('Odometer', _getOdometer()),
                  if (widget.job['created_at'] != null)
                    _infoRow(
                      'Job Created',
                      _formatDate(widget.job['created_at']),
                    ),
                  if (widget.job['completed_at'] != null)
                    _infoRow(
                      'Completed',
                      _formatDate(widget.job['completed_at']),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Services & Items List
            if (_complaints.isNotEmpty)
              _buildSection(
                icon: _isCourier ? Icons.inventory_2_outlined : Icons.build_outlined,
                title: _isCourier ? 'Packages / Items' : 'Services & Parts',
                color: const Color(0xFF059669),
                child: Column(
                  children: _complaints.map((c) => _lineItem(c)).toList(),
                ),
              ),

            if (_complaints.isNotEmpty) const SizedBox(height: 16),

            // Additional Work
            if (_suggestions.isNotEmpty)
              _buildSection(
                icon: Icons.add_task,
                title: 'Additional Work',
                color: Colors.teal,
                child: Column(
                  children: _suggestions.map((s) => _lineItem(s)).toList(),
                ),
              ),

            if (_suggestions.isNotEmpty) const SizedBox(height: 16),

            // Totals Card
            _buildTotalsCard(currency),

            // Billing Details Section
            const SizedBox(height: 16),
            _buildSection(
              icon: Icons.receipt_long,
              title: 'Billing & Tally Status',
              color: isBilled ? const Color(0xFF059669) : Colors.orange,
              child: Column(
                children: [
                  _infoRow(
                    'Billing Status',
                    _isConvertedInTally
                        ? 'Converted in Tally'
                        : (isBilled ? 'Marked as Billed from App' : 'Pending'),
                  ),
                  if (widget.job['job_card_id'] != null)
                    _infoRow('Order / JC No.', widget.job['job_card_id']),
                  if (widget.job['billed_at'] != null)
                    _infoRow('Billed On', _formatDate(widget.job['billed_at'])),
                  if (widget.job['voucher_type'] != null)
                    _infoRow('Voucher Type', widget.job['voucher_type']),
                  if (widget.job['tally_sync_status'] != null)
                    _infoRow('Tally Sync', widget.job['tally_sync_status'].toString().toUpperCase()),
                  if (widget.job['executive']?['username'] != null)
                    _infoRow('Staff / Executive', widget.job['executive']['username']),
                ],
              ),
            ),

            // ── Payment & Day-Book Reference Section ──
            const SizedBox(height: 16),
            _buildSection(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payment & Day-Book Reference',
              color: isBilled ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBilled) ...[
                    _infoRow('Payment Status', 'Paid & Recorded'),
                    if (widget.job['payment_method'] != null)
                      _infoRow('Payment Mode', widget.job['payment_method'].toString()),
                    if (widget.job['paid_at'] != null)
                      _infoRow('Payment Date', _formatDate(widget.job['paid_at'])),
                    if (widget.job['payment_notes'] != null && widget.job['payment_notes'].toString().trim().isNotEmpty)
                      _infoRow('Day-Book Notes', widget.job['payment_notes'].toString().trim()),
                    // If split payments available
                    if (widget.job['payments'] is List && (widget.job['payments'] as List).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Split Breakdown:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      ...(widget.job['payments'] as List).map((p) {
                        if (p is! Map) return const SizedBox();
                        final m = p['method'] ?? 'Payment';
                        final amt = NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(p['amount'] ?? 0);
                        final tid = p['transaction_id']?.toString() ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(_getPaymentIcon(m.toString()), size: 16, color: _getPaymentColor(m.toString())),
                                  const SizedBox(width: 8),
                                  Text(
                                    m.toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  if (tid.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text('($tid)', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                  ],
                                ],
                              ),
                              Text(amt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Not marked as billed yet. Tap "Mark Billed & Record Payment" below to save payment mode (GPay, PhonePe, Cash, Split) and day-book reference notes.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 80), // Padding for sticky bottom bar
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: (widget.job['status'] == AppConstants.statusEditRequested)
              ? SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_top_rounded, size: 20, color: Color(0xFFEA580C)),
                    label: const Text(
                      'Edit Requested (With Executive)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFB923C)),
                      backgroundColor: const Color(0xFFFFF7ED),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              : (isBilled
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openPaymentScreen,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: const Text(
                          'Edit Payment Details',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openPaymentScreen,
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const Text(
                          'Mark as Billed',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    )),
        ),
      ),
    );
  }

  Future<void> _openPaymentScreen() async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(job: widget.job, grandTotal: _grandTotal),
      ),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  IconData _getPaymentIcon(String method) {
    final m = method.toLowerCase();
    if (m.contains('gpay') || m.contains('google')) return Icons.account_balance_wallet_rounded;
    if (m.contains('phonepe') || m.contains('phone pe')) return Icons.phone_android_rounded;
    if (m.contains('paytm')) return Icons.account_balance_wallet_outlined;
    if (m.contains('cash')) return Icons.payments_rounded;
    if (m.contains('card')) return Icons.credit_card_rounded;
    if (m.contains('split')) return Icons.call_split_rounded;
    if (m.contains('upi')) return Icons.qr_code_2_rounded;
    if (m.contains('bank') || m.contains('net')) return Icons.account_balance_rounded;
    if (m.contains('cheque')) return Icons.description_outlined;
    return Icons.payment_rounded;
  }

  Color _getPaymentColor(String method) {
    final m = method.toLowerCase();
    if (m.contains('gpay') || m.contains('google')) return const Color(0xFF1A73E8);
    if (m.contains('phonepe') || m.contains('phone pe')) return const Color(0xFF5F259F);
    if (m.contains('paytm')) return const Color(0xFF0284C7);
    if (m.contains('cash')) return const Color(0xFF059669);
    if (m.contains('card')) return const Color(0xFF2563EB);
    if (m.contains('split')) return const Color(0xFF7C3AED);
    if (m.contains('upi')) return const Color(0xFFEA580C);
    if (m.contains('bank') || m.contains('net')) return const Color(0xFF475569);
    if (m.contains('cheque')) return const Color(0xFF7C3AED);
    return const Color(0xFF059669);
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _lineItem(Map<String, dynamic> item) {
    final String name = item['name'] ?? item['text'] ?? '-';
    final int qty = int.tryParse('${item['qty'] ?? item['count'] ?? 1}') ?? 1;
    final double unitPrice = ((item['unit_price'] ?? 0) as num).toDouble();
    final double amount = ((item['amount'] ?? 0) as num).toDouble();
    final double discount = ((item['discount'] ?? 0) as num).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (qty > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200, width: 0.8),
                        ),
                        child: Text(
                          unitPrice > 0 && qty > 1
                              ? 'Qty: $qty (@ ₹${unitPrice.toStringAsFixed(0)})'
                              : 'Qty: $qty',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                        ),
                      ),
                    if (discount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200, width: 0.8),
                        ),
                        child: Text(
                          'Disc: -₹${discount.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(NumberFormat currency) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.calculate_outlined, color: Colors.blue, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Summary & Totals', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _totalRow('Subtotal', _subtotal),
                if (_isCourier || _labourCost > 0)
                  _totalRow(_isCourier ? 'Delivery Charges' : 'Labour Charges', _labourCost),
                if (_discountAmount > 0)
                  _totalRow('Discount', -_discountAmount, color: Colors.red),
                if (_extraChargeAmount > 0)
                  _totalRow(_extraLabel.isNotEmpty ? _extraLabel : 'Extra Charges', _extraChargeAmount),
                if (_gstEnabled && _gstAmount > 0)
                  _totalRow('GST (${_gstPercent.toStringAsFixed(0)}%)', _gstAmount),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _totalRow(
                  'Grand Total',
                  _grandTotal,
                  isBold: true,
                  color: AppTheme.primaryColor,
                  fontSize: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool isBold = false, Color? color, double fontSize = 14}) {
    final isNegative = amount < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? AppTheme.textSecondary)),
          ),
          Text(
            '${isNegative ? '- ' : ''}${NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(amount.abs())}',
            style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.w700, color: color ?? AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}
