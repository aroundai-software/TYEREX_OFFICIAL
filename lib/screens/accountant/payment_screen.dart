// lib/screens/accountant/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_constants.dart';
import '../../utils/uuid_helper.dart';

class SplitPayment {
  String method;
  TextEditingController amountController;
  TextEditingController transactionIdController;

  static String formatAmount(double val) {
    if (val <= 0) return '';
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(2);
  }

  SplitPayment({
    required this.method,
    required double initialAmount,
  })  : amountController = TextEditingController(text: formatAmount(initialAmount)),
        transactionIdController = TextEditingController();

  void dispose() {
    amountController.dispose();
    transactionIdController.dispose();
  }
}

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  final double grandTotal;

  const PaymentScreen({super.key, required this.job, required this.grandTotal});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final supabase = Supabase.instance.client;
  final _notesController = TextEditingController();

  final List<String> _paymentMethods = [
    'GPay',
    'PhonePe',
    'Cash',
    'Card',
    'Paytm',
    'UPI',
    'Net Banking',
    'Bajaj Finance',
    'Cheque',
    'Credit',
    'Buyback',
    'Others',
  ];
  final List<SplitPayment> _splits = [];
  bool _isSubmitting = false;
  DateTime _paymentDate = DateTime.now();
  String _selectedVoucherType = 'GST SALES B2C';

  @override
  void initState() {
    super.initState();

    // 1. Pre-fill existing payments if available
    final rawPayments = widget.job['payments'];
    if (rawPayments is List && rawPayments.isNotEmpty) {
      for (final p in rawPayments) {
        if (p is Map) {
          final m = p['method']?.toString() ?? 'GPay';
          final amt = ((p['amount'] ?? 0) as num).toDouble();
          final tid = p['transaction_id']?.toString() ?? '';
          final split = SplitPayment(
            method: _paymentMethods.contains(m) ? m : 'GPay',
            initialAmount: amt > 0 ? amt : widget.grandTotal,
          );
          if (tid.isNotEmpty) {
            split.transactionIdController.text = tid;
          }
          _splits.add(split);
        }
      }
    }

    // 2. If no payment rows, check payment_method on report
    if (_splits.isEmpty) {
      final existingMethod = widget.job['payment_method']?.toString();
      final defaultMethod = (existingMethod != null && _paymentMethods.contains(existingMethod))
          ? existingMethod
          : 'GPay';
      _splits.add(SplitPayment(method: defaultMethod, initialAmount: widget.grandTotal));
    }

    // 3. Pre-fill notes
    final existingNotes = widget.job['payment_notes']?.toString();
    if (existingNotes != null && existingNotes.isNotEmpty) {
      _notesController.text = existingNotes;
    }

    // 4. Pre-fill payment date
    final existingDateStr = widget.job['paid_at'] ?? widget.job['billed_at'];
    if (existingDateStr != null && existingDateStr.toString().isNotEmpty) {
      try {
        _paymentDate = DateTime.parse(existingDateStr.toString()).toLocal();
      } catch (_) {}
    }

    // 5. Determine voucher type
    final existingVoucher = widget.job['voucher_type']?.toString();
    if (existingVoucher != null && existingVoucher.isNotEmpty) {
      _selectedVoucherType = existingVoucher;
    } else {
      final gst = widget.job['gst_percent'];
      final hasGst = gst != null && (gst is num ? gst > 0 : (double.tryParse(gst.toString()) ?? 0) > 0);
      if (hasGst) {
        _selectedVoucherType = 'GST SALES B2C';
      } else {
        _selectedVoucherType = 'SALES B2C';
      }
    }
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _paymentDate) {
      setState(() {
        // Keep the current time, just change the date
        final now = DateTime.now();
        _paymentDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
          now.second,
        );
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (var split in _splits) {
      split.dispose();
    }
    super.dispose();
  }

  void _addSplit() {
    double currentTotal = _splits.fold(0.0, (sum, split) {
      return sum + (double.tryParse(split.amountController.text) ?? 0.0);
    });
    double remaining = widget.grandTotal - currentTotal;
    if (remaining < 0) remaining = 0;
    
    setState(() {
      _splits.add(SplitPayment(method: 'Cash', initialAmount: remaining));
    });
  }

  void _removeSplit(int index) {
    setState(() {
      _splits[index].dispose();
      _splits.removeAt(index);
      
      // Re-balance if there are still splits left
      if (_splits.length > 1) {
        _onAmountChanged(0, _splits[0].amountController.text);
      }
    });
  }

  void _onAmountChanged(int changedIndex, String value) {
    if (_splits.length < 2) {
      setState(() {});
      return;
    }
    
    // The "buffer" split that auto-adjusts is usually the last one,
    // unless the user is currently editing the last one.
    int targetIndex = (changedIndex == _splits.length - 1) 
        ? _splits.length - 2 
        : _splits.length - 1;
        
    // Sum up everything EXCEPT the buffer split
    double sumOthers = 0;
    for (int i = 0; i < _splits.length; i++) {
      if (i == targetIndex) continue;
      sumOthers += double.tryParse(_splits[i].amountController.text) ?? 0.0;
    }
    
    double remaining = widget.grandTotal - sumOthers;
    if (remaining < 0) remaining = 0;
    
    _splits[targetIndex].amountController.text = SplitPayment.formatAmount(remaining);
    
    setState(() {});
  }

  Future<void> _recordPayment() async {
    // If only 1 payment (single full payment), automatically ensure exact grandTotal
    if (_splits.length == 1) {
      final text = _splits[0].amountController.text.trim();
      final parsed = double.tryParse(text);
      if (parsed == null || (parsed - widget.grandTotal).abs() < 1.0) {
        _splits[0].amountController.text = SplitPayment.formatAmount(widget.grandTotal);
      }
    }

    // Validate amounts
    double totalEntered = _splits.fold(0.0, (sum, split) {
      return sum + (double.tryParse(split.amountController.text) ?? 0.0);
    });

    if ((totalEntered - widget.grandTotal).abs() > 0.05) {
      final String msg = _splits.length > 1
          ? 'Total split amount (₹${totalEntered.toStringAsFixed(2)}) must exactly equal Grand Total (₹${widget.grandTotal.toStringAsFixed(2)})'
          : 'Payment amount (₹${totalEntered.toStringAsFixed(2)}) must equal Grand Total (₹${widget.grandTotal.toStringAsFixed(2)})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final nowUtcIso = _paymentDate.toUtc().toIso8601String();
      final reportId = int.tryParse(widget.job['id'].toString()) ?? widget.job['id'];
      final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
      final paymentMethod = _splits.length > 1 ? 'Split' : _splits.first.method;

      // 1. Update reports table (App reference only - DO NOT touch is_converted)
      try {
        await supabase.from('reports').update({
          'billing_status': AppConstants.statusPaid,
          'paid_at': nowUtcIso,
          'payment_method': paymentMethod,
          'payment_notes': notes,
        }).eq('id', reportId);
      } catch (e1) {
        debugPrint('⚠️ update report core payload failed: $e1, trying minimum fallback');
        try {
          await supabase.from('reports').update({
            'billing_status': AppConstants.statusPaid,
            'paid_at': nowUtcIso,
          }).eq('id', reportId);
        } catch (e2) {
          debugPrint('⚠️ minimum fallback failed: $e2');
        }
      }

      // 2. Clean up any existing payments for this report_id first so we update/replace rather than create duplicate rows
      try {
        await supabase.from('payments').delete().eq('report_id', reportId);
      } catch (delErr) {
        debugPrint('⚠️ payments.delete failed before insert: $delErr');
      }

      // Insert into payments table
      for (var split in _splits) {
        final amount = double.tryParse(split.amountController.text) ?? 0.0;
        if (amount <= 0) continue; // Skip 0 amounts just in case

        final tid = split.transactionIdController.text.trim();
        final alterId = generateUuidV4();
        
        // Base payments schema columns
        final Map<String, dynamic> paymentData = {
          'report_id': reportId,
          'method': split.method,
          'amount': amount,
          'transaction_id': tid.isNotEmpty ? tid : null,
          'paid_at': nowUtcIso,
          'voucher_type': _selectedVoucherType,
          'tally_sync_status': 'pending',
          'alter_id': alterId,
          'notes': notes,
        };

        // Try insert with progressive column exclusion only for offending column
        bool inserted = false;
        Map<String, dynamic> attemptData = Map<String, dynamic>.from(paymentData);

        while (!inserted) {
          try {
            await supabase.from('payments').insert(attemptData);
            inserted = true;
          } catch (insertError) {
            final errStr = insertError.toString();
            debugPrint('⚠️ payments.insert failed: $errStr');

            bool removedSpecific = false;
            for (final col in ['notes', 'alter_id', 'tally_sync_status', 'company_id', 'branch_name', 'branch_id', 'company_name', 'Guid', 'voucher_type']) {
              if (attemptData.containsKey(col) && (errStr.contains(col) || errStr.toLowerCase().contains(col.toLowerCase()))) {
                attemptData.remove(col);
                removedSpecific = true;
                debugPrint('⚠️ Removed invalid column "$col" from payments insert');
                break;
              }
            }

            if (!removedSpecific) {
              if (attemptData.containsKey('company_id')) {
                attemptData.remove('company_id');
              } else if (attemptData.containsKey('notes')) {
                attemptData.remove('notes');
              } else if (attemptData.containsKey('alter_id')) {
                attemptData.remove('alter_id');
              } else if (attemptData.containsKey('tally_sync_status')) {
                attemptData.remove('tally_sync_status');
              } else if (attemptData.containsKey('branch_name')) {
                attemptData.remove('branch_name');
              } else if (attemptData.containsKey('branch_id')) {
                attemptData.remove('branch_id');
              } else if (attemptData.containsKey('company_name')) {
                attemptData.remove('company_name');
              } else if (attemptData.containsKey('Guid')) {
                attemptData.remove('Guid');
              } else if (attemptData.containsKey('voucher_type')) {
                attemptData.remove('voucher_type');
              } else {
                // Absolute fallback
                await supabase.from('payments').insert({
                  'report_id': reportId,
                  'method': split.method,
                  'amount': amount,
                  'transaction_id': tid.isNotEmpty ? tid : null,
                  'paid_at': nowUtcIso,
                });
                inserted = true;
              }
            }
          }
        }
      }

      // Update local object (without touching is_converted)
      widget.job['billing_status'] = AppConstants.statusPaid;
      widget.job['paid_at'] = nowUtcIso;
      widget.job['payment_method'] = paymentMethod;
      widget.job['payment_notes'] = notes;
      widget.job['voucher_type'] = _selectedVoucherType;
      widget.job['payments'] = _splits.map((s) => {
        'method': s.method,
        'amount': double.tryParse(s.amountController.text) ?? 0.0,
        'transaction_id': s.transactionIdController.text.trim(),
        'paid_at': nowUtcIso,
        'notes': notes,
      }).toList();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_splits.length > 1 
              ? '✅ Split payment saved & Marked as Billed from App!'
              : '✅ Paid via $paymentMethod & Marked as Billed from App!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Payment Methods'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount due banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('Amount Due', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    currency.format(widget.grandTotal),
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.job['vehicles']?['Vehicle Number'] ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            
            // Payment Date Picker
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Payment Date', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                InkWell(
                  onTap: _pickPaymentDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('dd MMM yyyy').format(_paymentDate),
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Voucher Type Selection
            _buildVoucherTypeSelector(),

            const SizedBox(height: 24),

            const Text('Payment Methods', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),

            // Splits list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _splits.length,
              itemBuilder: (context, index) {
                final split = _splits[index];
                final showTransactionId = split.method != 'Cash';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _splits.length > 1 ? 'Payment Mode #${index + 1}' : 'Payment Mode & Amount',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          if (_splits.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _removeSplit(index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Payment method selector inside split
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _paymentMethods.map((method) {
                          final isSelected = split.method == method;
                          final methodColor = _colorForMethod(method);
                          return GestureDetector(
                            onTap: () => setState(() => split.method = method),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? methodColor : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? methodColor : const Color(0xFFE5E7EB),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_iconForMethod(method), size: 15, color: isSelected ? Colors.white : methodColor),
                                  const SizedBox(width: 5),
                                  Text(
                                    method,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      
                      // Amount
                      TextField(
                        controller: split.amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Amount (₹)',
                          hintText: SplitPayment.formatAmount(widget.grandTotal),
                          suffixIcon: TextButton(
                            onPressed: () {
                              setState(() {
                                split.amountController.text = widget.grandTotal % 1 == 0
                                    ? widget.grandTotal.toInt().toString()
                                    : widget.grandTotal.toStringAsFixed(2);
                              });
                            },
                            child: const Text('Full Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (val) => _onAmountChanged(index, val),
                      ),
                      
                      if (showTransactionId) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: split.transactionIdController,
                          decoration: InputDecoration(
                            labelText: 'Ref / Txn ID / UTR (optional)',
                            hintText: 'e.g., GPay UTR, UPI Ref, Cheque No.',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            Center(
              child: TextButton.icon(
                onPressed: _addSplit,
                icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                label: const Text('+ Add Split Payment Mode', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),

            const SizedBox(height: 24),

            const Text('Day-Book Notes / Payment Reference', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            const Text('Enter reference notes for book keeping (e.g. Daybook page no., cash notes, customer split remark)', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),

            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Register page 42, GPay #987654, Cash collected at reception',
                hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _recordPayment,
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle, size: 20),
                label: Text(
                  _isSubmitting ? 'Saving...' : 'Save',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherTypeSelector() {
    final options = [
      {
        'type': 'SALES B2C',
        'title': 'Sales B2C',
        'subtitle': 'Non-GST Retail',
        'icon': Icons.person_outline,
        'badgeColor': const Color(0xFF6366F1),
      },
      {
        'type': 'GST SALES B2C',
        'title': 'GST Sales B2C',
        'subtitle': 'GST Consumer',
        'icon': Icons.receipt_long,
        'badgeColor': const Color(0xFF0EA5E9),
      },
      {
        'type': 'GST SALES B2B',
        'title': 'GST Sales B2B',
        'subtitle': 'GST Business',
        'icon': Icons.business,
        'badgeColor': const Color(0xFF10B981),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: AppTheme.primaryColor),
            SizedBox(width: 6),
            Text(
              'Voucher Type',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;
            if (isNarrow) {
              return Column(
                children: options.map((opt) => _buildVoucherOptionCard(opt, isFullWidth: true)).toList(),
              );
            }
            return Row(
              children: options.map((opt) => Expanded(child: _buildVoucherOptionCard(opt))).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVoucherOptionCard(Map<String, dynamic> opt, {bool isFullWidth = false}) {
    final isSelected = _selectedVoucherType == opt['type'];
    final badgeColor = opt['badgeColor'] as Color;

    return Padding(
      padding: EdgeInsets.only(
        right: isFullWidth ? 0 : 8.0,
        bottom: isFullWidth ? 8.0 : 0,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedVoucherType = opt['type'] as String;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? badgeColor.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? badgeColor : const Color(0xFFE5E7EB),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: badgeColor.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isSelected ? badgeColor : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  opt['icon'] as IconData,
                  size: 16,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt['title'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? badgeColor : AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opt['subtitle'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? badgeColor.withValues(alpha: 0.85) : AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: badgeColor, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForMethod(String method) {
    switch (method) {
      case 'GPay':
        return Icons.account_balance_wallet_rounded;
      case 'PhonePe':
        return Icons.phone_android_rounded;
      case 'Paytm':
        return Icons.account_balance_wallet_outlined;
      case 'Cash':
        return Icons.payments_rounded;
      case 'Card':
        return Icons.credit_card_rounded;
      case 'UPI':
        return Icons.qr_code_2_rounded;
      case 'Net Banking':
        return Icons.account_balance_rounded;
      case 'Bajaj Finance':
        return Icons.storefront_rounded;
      case 'Cheque':
        return Icons.description_outlined;
      case 'Credit':
        return Icons.history_rounded;
      case 'Buyback':
        return Icons.swap_horiz_rounded;
      case 'Others':
      default:
        return Icons.more_horiz_rounded;
    }
  }

  Color _colorForMethod(String method) {
    switch (method) {
      case 'GPay':
        return const Color(0xFF1A73E8);
      case 'PhonePe':
        return const Color(0xFF5F259F);
      case 'Cash':
        return const Color(0xFF059669);
      case 'Card':
        return const Color(0xFF2563EB);
      case 'Paytm':
        return const Color(0xFF0284C7);
      case 'UPI':
        return const Color(0xFFEA580C);
      case 'Net Banking':
        return const Color(0xFF475569);
      case 'Bajaj Finance':
        return const Color(0xFF0284C7);
      case 'Cheque':
        return const Color(0xFF7C3AED);
      case 'Credit':
        return const Color(0xFFD97706);
      case 'Buyback':
        return const Color(0xFF0D9488);
      case 'Others':
      default:
        return const Color(0xFF64748B);
    }
  }
}
