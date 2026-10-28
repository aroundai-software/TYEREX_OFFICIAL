// lib/screens/job_card_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'update_screen.dart';
import 'continuous_camera_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../screens/custom_scanner_screen.dart';
import '../screens/multi_wheel_camera_screen.dart';
import '../screens/unlimited_camera_screen.dart';
import '../screens/number_plate_scanner_screen.dart';
import '../screens/odometer_camera_screen.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:archive/archive.dart';
import '../utils/app_constants.dart';
import '../utils/validators.dart';
import '../utils/date_utils.dart';
import 'package:intl/intl.dart';
import '../widgets/service_catalog_picker.dart';
import '../utils/vehicle_number_utils.dart';
import '../widgets/error_display.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_cached_image.dart';
// Existing imports
import '../services/ocr_service.dart';
import '../services/supabase_service.dart';
import '../services/local_media_service.dart';
import '../services/vehicle_service.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../providers/report_provider.dart';
import '../providers/admin_settings_provider.dart';
import '../widgets/brand_model_search_dropdown.dart';
import '../widgets/typeahead_field.dart';
import '../widgets/company_switcher_badge.dart';
import '../widgets/tyre_catalog_picker.dart';
import '../services/client_features_service.dart';

class JobCardScreen extends StatefulWidget {
  final int? bookingId;
  final String? customerName;
  final String? customerPhone;
  final Map<String, dynamic>? draftJob;
  
  const JobCardScreen({
    super.key,
    this.bookingId,
    this.customerName,
    this.customerPhone,
    this.draftJob,
  });

  @override
  State<JobCardScreen> createState() => _JobCardScreenState();
}

class _JobCardScreenState extends State<JobCardScreen> {
  final ScrollController _mainScrollController = ScrollController();
  // Controllers
  final _vehicleNumberController = TextEditingController();
  final _newVehicleNameController = TextEditingController();
  final _newColorController = TextEditingController();
  final _newOdometerController = TextEditingController();
  final _newClientNameController = TextEditingController();
  final _newClientPhoneController = TextEditingController();
  final _newClientMobileController = TextEditingController();
  final _odometerController = TextEditingController();
  final _complaintInputController = TextEditingController();
  final _complaintAmountController = TextEditingController();
  final _complaintCountController = TextEditingController(text: '1');
  final _laborCostController = TextEditingController(); // Added Labour Cost Controller
  final FocusNode _complaintFocusNode = FocusNode();
  final TextEditingController _tyreBrandController = TextEditingController();
  final TextEditingController _tyreModelController = TextEditingController();
  final TextEditingController _tyreSizeController = TextEditingController();
  final TextEditingController _tyreLiSiController = TextEditingController();
  final TextEditingController _tyreCountController = TextEditingController();
  final TextEditingController _tyrePriceController = TextEditingController();
  final TextEditingController _tyreTotalController = TextEditingController();

  String? get _selectedGlobalTyreBrand => _tyreBrandController.text.trim().isNotEmpty ? _tyreBrandController.text.trim() : null;
  String? get _selectedGlobalTyreModel => _tyreModelController.text.trim().isNotEmpty ? _tyreModelController.text.trim() : null;
  String? get _selectedGlobalTyreSize => _tyreSizeController.text.trim().isNotEmpty ? _tyreSizeController.text.trim() : null;
  String? get _selectedGlobalTyreLiSi => _tyreLiSiController.text.trim().isNotEmpty ? _tyreLiSiController.text.trim() : null;

  set _selectedGlobalTyreBrand(String? val) => _tyreBrandController.text = val ?? '';
  set _selectedGlobalTyreModel(String? val) => _tyreModelController.text = val ?? '';
  set _selectedGlobalTyreSize(String? val) => _tyreSizeController.text = val ?? '';
  set _selectedGlobalTyreLiSi(String? val) => _tyreLiSiController.text = val ?? '';

  // Alloy State
  bool _showAlloySection = false;
  final TextEditingController _alloyBrandController = TextEditingController();
  final TextEditingController _alloyModelController = TextEditingController();
  final TextEditingController _alloySizeController = TextEditingController();
  final TextEditingController _alloyCountController = TextEditingController(text: '4');
  final TextEditingController _alloyPriceController = TextEditingController();
  final TextEditingController _alloyTotalController = TextEditingController();

  final List<String> _defaultAlloyBrands = [
    'Neo Wheels',
    'Plati',
    'Momo',
    'Enkei',
    'Lenso',
    'BBS',
    'Fuel',
    'Inforged',
    'Freeman',
    'Uno',
    'Konig',
    'Advanti',
    'O.Z Racing',
    'Sparco',
    'TSW',
    'Borbet',
    'HRE',
    'Vossen',
    'Rays / Volk',
    'Work',
    'Rotiform',
    'Yokohama Wheels',
    'Apollo Alloys',
    'Steel / OEM',
  ];

  final List<String> _defaultAlloySizes = [
    '12"',
    '13"',
    '14"',
    '15"',
    '16"',
    '17"',
    '18"',
    '19"',
    '20"',
    '21"',
    '22"',
    '15x6.5J',
    '16x7J',
    '17x7.5J',
    '18x8J',
    '18x8.5J',
    '19x8.5J',
    '20x9J',
  ];

  List<Map<String, dynamic>> _alloyCatalog = [];
  String? _selectedOwnerId;

  // Owner Master Field
  final _ownerGstController = TextEditingController();

  // Supabase
  final supabase = Supabase.instance.client;
  final vehicleService = VehicleService();


  // State Management
  bool _isLoading = false;
  bool _isSaving = false; // Synchronous mutex lock against rapid multi-clicks


  String? _searchError;
  Map<String, dynamic>? _vehicleDetails;
  bool _showCreateVehicleForm = false;
  // ✅ True when the screen is loaded from a vehicle job card draft (existing vehicle)
  // Used to skip the vehicle search bar and creation form entirely
  bool _isVehicleJobCardDraft = false;
  dynamic _loadedRegistrationDraftId;
  int? _currentVehicleId;
  int? _lastKnownOdometer;

  // ✅ Add flags to track if details differ
  bool _clientNameDiffers = false;
  bool _clientPhoneDiffers = false;
  bool _isBuyback = false;

  // ✅ Search by Mobile variables
  bool _searchByMobile = false;
  final _mobileSearchController = TextEditingController();
  String? _mobileSearchError;

  // Courier State
  bool _isCourierMode = false;
  final _courierNameController = TextEditingController();
  final _courierPhoneController = TextEditingController();
  final _courierAddressController = TextEditingController();
  final _courierGstController = TextEditingController();
  final List<dynamic> _courierPhotos = [];
  String _courierCategory = 'Tyre'; // 'Tyre' or 'Alloy'
  String? _courierProductBrand;
  String? _courierProductModel;
  String? _courierProductSize;


  
  final _courierProductPriceController = TextEditingController();
  final _courierProductQtyController = TextEditingController(text: '1');
  final List<Map<String, dynamic>> _courierProductsList = [];
  int? _editingCourierProductIndex;

  void _addCourierProduct() {
    if (_courierProductBrand == null || _courierProductModel == null || _courierProductSize == null) {
      _showErrorSnackBar('Please select Brand, Model, and Size.');
      return;
    }
    
    final price = double.tryParse(_courierProductPriceController.text) ?? 0.0;
    final qty = int.tryParse(_courierProductQtyController.text) ?? 1;
    final isAlloy = _courierCategory == 'Alloy';
    final categoryPrefix = isAlloy ? 'Alloy - ' : 'Tyre - ';

    setState(() {
      if (_editingCourierProductIndex != null) {
        final existingImages = _courierProductsList[_editingCourierProductIndex!]['qr_images'] as List<dynamic>? ?? [];
        _courierProductsList[_editingCourierProductIndex!] = {
          'category': _courierCategory,
          'brand': _courierProductBrand,
          'model': _courierProductModel,
          'size': _courierProductSize,
          'name': '$categoryPrefix$_courierProductBrand $_courierProductModel - $_courierProductSize',
          'price': price,
          'qty': qty,
          'qr_images': existingImages, 
        };
        _editingCourierProductIndex = null;
      } else {
        int existingIndex = _courierProductsList.indexWhere((p) => 
          (p['category'] ?? (p['name']?.toString().startsWith('Alloy') == true ? 'Alloy' : 'Tyre')) == _courierCategory &&
          p['brand'] == _courierProductBrand && 
          p['model'] == _courierProductModel && 
          p['size'] == _courierProductSize
        );

        if (existingIndex != -1) {
          _courierProductsList[existingIndex]['qty'] = (_courierProductsList[existingIndex]['qty'] as int) + qty;
          _courierProductsList[existingIndex]['price'] = price; 
        } else {
          _courierProductsList.add({
            'category': _courierCategory,
            'brand': _courierProductBrand,
            'model': _courierProductModel,
            'size': _courierProductSize,
            'name': '$categoryPrefix$_courierProductBrand $_courierProductModel - $_courierProductSize',
            'price': price,
            'qty': qty,
            'qr_images': <dynamic>[], 
          });
        }
      }
      
      _courierProductBrand = null;
      _courierProductModel = null;
      _courierProductSize = null;
      _courierProductPriceController.clear();
      _courierProductQtyController.text = '1';
    });
  }

  void _deleteCourierProduct(int index) {
    setState(() {
      _courierProductsList.removeAt(index);
    });
  }

  void _editCourierProduct(int index) {
    final p = _courierProductsList[index];
    setState(() {
      _courierCategory = (p['category'] ?? (p['name']?.toString().startsWith('Alloy') == true ? 'Alloy' : 'Tyre')).toString();
      _courierProductBrand = p['brand'];
      _courierProductModel = p['model'];
      _courierProductSize = p['size'];
      _courierProductQtyController.text = p['qty'].toString();
      _courierProductPriceController.text = p['price'].toString();
      _editingCourierProductIndex = index;
    });
  }

  void _cancelEditCourierProduct() {
    setState(() {
      _editingCourierProductIndex = null;
      _courierProductBrand = null;
      _courierProductModel = null;
      _courierProductSize = null;
      _courierProductPriceController.clear();
      _courierProductQtyController.text = '1';
    });
  }

  Future<void> _scanCourierProductQR(int index) async {
    final qty = (_courierProductsList[index]['qty'] is int)
        ? _courierProductsList[index]['qty'] as int
        : (int.tryParse(_courierProductsList[index]['qty']?.toString() ?? '1') ?? 1);
    final currentPhotos = _courierProductsList[index]['qr_images'] as List<dynamic>? ?? [];
    
    int remaining = qty - currentPhotos.length;
    if (remaining <= 0) {
      _showErrorSnackBar('You have already scanned all QRs for this product.');
      return;
    }

    final List<String> targets = List.generate(remaining, (i) => 'QR Code ${i + 1} of $remaining');
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiWheelCameraScreen(targets: targets),
      ),
    );

    if (result != null && result is Map) {
      List<dynamic> images = List<dynamic>.from(currentPhotos);
      for (var file in result.values) {
        try {
          images.add(await file.readAsBytes());
        } catch (e) {
          debugPrint('Error reading QR file: $e');
        }
      }
      setState(() {
        _courierProductsList[index]['qr_images'] = images;
      });
    }
  }

  void _viewCourierQR(int productIndex, int photoIndex) {
    showDialog(
      context: context,
      builder: (context) {
        final images = _courierProductsList[productIndex]['qr_images'] as List<dynamic>;
        final imageItem = images[photoIndex];
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  InteractiveViewer(
                    child: imageItem is String ? AppCachedImage(imageUrl: imageItem, fit: BoxFit.contain) : Image.memory(imageItem as Uint8List, fit: BoxFit.contain),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    images.removeAt(photoIndex);
                  });
                  Navigator.pop(context);
                  _scanCourierProductQR(productIndex); 
                },
                icon: const Icon(Icons.delete),
                label: const Text('Delete & Retake'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------
  // Sharing Helpers
  // -------------------
  Future<void> _shareTyreImage(String wheel) async {
    final bytes = _tyreQRImages[wheel];
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$wheel-qr.png');
    await file.writeAsBytes(bytes);
    await Share.shareFiles([file.path], text: 'Tyre QR for $wheel');
  }

  Future<void> _shareAllTyresAsZip() async {
    final archive = Archive();
    for (final wheel in _requiredWheels) {
      final bytes = _tyreQRImages[wheel];
      if (bytes != null) {
        archive.addFile(ArchiveFile('$wheel-qr.png', bytes.length, bytes));
      }
    }
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;
    final dir = await getTemporaryDirectory();
    final zipFile = File('${dir.path}/tyre_qrs_and_pdfs.zip');
    await zipFile.writeAsBytes(zipData);
    await Share.shareFiles([zipFile.path], text: 'All tyre QR images and PDFs');
  }

  // Share a PDF containing the tyre QR image and specs
  Future<void> _shareTyrePdf(String wheel) async {
    final bytes = _tyreQRImages[wheel];
    if (bytes == null) return;
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Tyre QR for $wheel', style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 10),
            pw.Image(image, width: 200, height: 200),
            pw.SizedBox(height: 10),
            pw.Text('Spec: ${_tyreSpecControllers[wheel]?.text ?? ''}'),
          ],
        ),
      ),
    );
    final dir = await getTemporaryDirectory();
    final pdfFile = File('${dir.path}/$wheel-qr.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    await Share.shareFiles([pdfFile.path], text: 'Tyre PDF for $wheel');
  }

  // State variables for owner details
  Map<String, dynamic>? _ownerDetails;

  // ✅ NEW: Validation error states
  String? _vehicleNumberError;
  String? _phoneError;
  String? _odometerError;

  // Dropdown State
  bool _isFoundInTally = false;
  List<Map<String, dynamic>> _vehicleModelsCache = [];
  List<String> _uniqueBrands = [];
  String? _selectedBrand;
  int? _selectedModelId;
  String? _selectedModelName;

  // Job Card Data
  final List<Map<String, dynamic>> _complaints = [];
  final List<Offset> _damageMarks = [];
  
  // Media & Barcode
  final Map<String, dynamic> _wheelPhotos = {};
  final List<dynamic> _vehiclePhotos = [];
  dynamic _odometerPhoto;
  
  // Tyre Warranty Details
  final Map<String, TextEditingController> _tyreQRControllers = {};
  final Map<String, TextEditingController> _tyreSpecControllers = {};
  final Map<String, dynamic> _tyreQRImages = {};
  
  final List<String> _requiredWheels = [
    'Front Left',
    'Rear Left',
    'Rear Right',
    'Front Right',
    'Stepney'
  ];
  final GlobalKey _imageKey = GlobalKey();

  // Media
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioPath;
  bool _isRecording = false;

  List<Map<String, dynamic>> _allTechnicians = [];
  List<Map<String, dynamic>> _technicianAssignments = [];
  List<Map<String, dynamic>> _serviceCatalog = [];
  Future<bool>? _featureCheckFuture;

  @override
  void initState() {
    super.initState();
    _featureCheckFuture = ClientFeaturesService().checkFeatureStatus('jobcards');
    _fetchVehicleModels();
    _fetchTechnicians();
    _fetchServiceCatalog();
    _fetchTyreCatalog();
    _fetchAlloyCatalog();
    
    // Initialize tyre controllers
    for (String wheel in _requiredWheels) {
      _tyreQRControllers[wheel] = TextEditingController();
      _tyreSpecControllers[wheel] = TextEditingController();
    }

    // Prefill customer details if available (from bookings)
    if (widget.customerName != null) {
      _newClientNameController.text = widget.customerName!;
    }
    if (widget.customerPhone != null) {
      _newClientPhoneController.text = widget.customerPhone!;
    }
    
    if (widget.draftJob != null) {
      final marksRaw = widget.draftJob!['marks'];
      Map<String, dynamic> marks = {};
      if (marksRaw != null) {
        if (marksRaw is String) {
          try { marks = jsonDecode(marksRaw); } catch (_) {}
        } else if (marksRaw is Map) {
          marks = Map<String, dynamic>.from(marksRaw);
        }
      }
      
      final bool isCourier = marks['is_courier'] == true ||
          marks['is_courier'] == 'true' ||
          (widget.draftJob!['vehicle_id'] == null &&
              (widget.draftJob!['complaint']?.toString().contains('Courier') == true ||
                  widget.draftJob!['job_card_id']?.toString().contains('COU') == true));
      _isCourierMode = isCourier;

      if (isCourier) {
        _courierNameController.text = (widget.draftJob!['Owner name'] ?? widget.draftJob!['owner_name'] ?? '').toString();
        _courierPhoneController.text = (widget.draftJob!['client_phone'] ?? widget.draftJob!['phone'] ?? '').toString();
        _courierAddressController.text = (marks['address'] ?? '').toString();
        _courierGstController.text = (marks['gst_no'] ?? '').toString();
        
        final productsList = marks['products'];
        if (productsList != null && productsList is List) {
          _courierProductsList.clear();
          for (var p in productsList) {
            final category = (p['category'] ?? (p['is_alloy'] == true ? 'Alloy' : ((p['name'] ?? '').toString().startsWith('Alloy') ? 'Alloy' : 'Tyre'))).toString();
            _courierProductsList.add({
              'category': category,
              'brand': p['brand'],
              'model': p['model'],
              'size': p['size'],
              'name': p['name'] ?? '$category ${p['brand'] ?? ''} ${p['model'] ?? ''} - ${p['size'] ?? ''}',
              'price': double.tryParse(p['price']?.toString() ?? '0') ?? 0.0,
              'qty': int.tryParse(p['qty']?.toString() ?? '1') ?? 1,
              'qr_images': <dynamic>[],
            });
          }
        }
      } else {
        // ✅ It's a vehicle job card draft — mark it so UI hides search+create form
        _isVehicleJobCardDraft = true;
        _loadDraftIntoForm(widget.draftJob!, showSnackBar: false);
      }
      
      _loadDraftMedia(widget.draftJob!);
    }
  }

  Future<void> _loadDraftMedia(Map<String, dynamic> draftJob) async {
    final photoUrlsRaw = draftJob['photo_urls'];
    if (photoUrlsRaw == null) return;
    
    List<String> urls = [];
    if (photoUrlsRaw is String) {
      try { urls = List<String>.from(jsonDecode(photoUrlsRaw)); } catch (_) {}
    } else if (photoUrlsRaw is List) {
      urls = List<String>.from(photoUrlsRaw.map((e) => e.toString()));
    }

    for (String url in urls) {
      try {
        // ─────────────── COURIER MEDIA ───────────────
        if (url.contains('_tyreqr_product_')) {
          // Format: job_{id}_tyreqr_product_{i}_qr_{j}_{timestamp}.jpg
          final match = RegExp(r'product_(\d+)_qr_(\d+)').firstMatch(url);
          if (match != null) {
            final productIndex = int.parse(match.group(1)!);
            if (productIndex < _courierProductsList.length) {
              if (mounted) {
                setState(() {
                  (_courierProductsList[productIndex]['qr_images'] as List<dynamic>).add(url);
                });
              }
            }
          }

        // ─────────────── VEHICLE TYRE QR IMAGES ───────────────
        // Format: job_{id}_tyreqr_{position}_{timestamp}.jpg
        } else if (url.contains('_tyreqr_') && !url.contains('_tyreqr_product_')) {
          // Extract position from filename, e.g. tyreqr_Front_Left_
          final match = RegExp(r'_tyreqr_(.+?)_\d+\.jpg').firstMatch(url);
          if (match != null) {
            // Reconstruct position with spaces (was saved with underscores)
            final rawPos = match.group(1)!.replaceAll('_', ' ');
            // Find the closest matching wheel position
            final position = _requiredWheels.firstWhere(
              (w) => w.replaceAll(' ', '_') == match.group(1)!,
              orElse: () => rawPos,
            );
            if (mounted) {
              setState(() {
                _tyreQRImages[position] = url;
              });
            }
          }

        // ─────────────── VEHICLE WHEEL PHOTOS ───────────────
        // Format: job_{id}_wheel_{position}_{timestamp}.jpg
        } else if (url.contains('_wheel_')) {
          final match = RegExp(r'_wheel_(.+?)_\d+\.jpg').firstMatch(url);
          if (match != null) {
            final rawPos = match.group(1)!;
            final position = _requiredWheels.firstWhere(
              (w) => w.replaceAll(' ', '_') == rawPos,
              orElse: () => rawPos.replaceAll('_', ' '),
            );
            if (mounted) {
              setState(() {
                _wheelPhotos[position] = url;
              });
            }
          }

        // ─────────────── VEHICLE / PACKAGE PHOTOS ───────────────
        // Format: job_{id}_vehicle_{i}_{timestamp}.jpg  (vehicle) or courier package
        } else if (url.contains('_vehicle_')) {
          if (mounted) {
            setState(() {
              if (_isCourierMode) {
                _courierPhotos.add(url);
              } else {
                _vehiclePhotos.add(url);
              }
            });
          }

        // ─────────────── ODOMETER PHOTO ───────────────
        // Format: job_{id}_odometer_{timestamp}.jpg
        } else if (url.contains('_odometer_')) {
          if (mounted) {
            setState(() {
              _odometerPhoto = url;
            });
          }
        }
      } catch (e) {
        debugPrint('Error assigning draft media $url: $e');
      }
    }
  }

  Future<void> _fetchTechnicians() async {
    try {
      final supabaseService = SupabaseService();
      final techs = await supabaseService.getAllTechnicians();
      if (mounted) {
        setState(() {
          _allTechnicians = techs;
        });
      }
    } catch (e) {
      debugPrint('Failed to load technicians: $e');
    }
  }

  Future<void> _fetchServiceCatalog() async {
    try {
      final supabaseService = SupabaseService();
      final catalog = await supabaseService.getServiceCatalog();
      if (mounted) {
        setState(() {
          _serviceCatalog = catalog;
        });
      }
    } catch (e) {
      debugPrint('Error fetching service catalog: $e');
    }
  }

  List<Map<String, dynamic>> _tyreCatalog = [];

  Future<void> _fetchTyreCatalog() async {
    try {
      final supabaseService = SupabaseService();
      final catalog = await supabaseService.getTyreCatalog();
      if (mounted) {
        setState(() {
          _tyreCatalog = catalog;
        });
      }
    } catch (e) {
      debugPrint('Error fetching tyre catalog: $e');
    }
  }

  Future<void> _fetchAlloyCatalog() async {
    try {
      final catalog = await SupabaseService().getAlloyCatalog();
      if (mounted) {
        setState(() {
          _alloyCatalog = catalog;
        });
      }
    } catch (_) {
      // Fall back to default alloy brand/size suggestions gracefully
    }
  }

  void _applyOwner(Map<String, dynamic> owner) {
    final phone = (owner['PhoneNumber'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final mobile = (owner['MobileNumber'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    String last10(String value) => value.length >= 10 ? value.substring(value.length - 10) : value;
    setState(() {
      _selectedOwnerId = owner['id']?.toString();
      _ownerDetails = owner;
      _newClientNameController.text = (owner['Owner name'] ?? '').toString();
      if (phone.isNotEmpty) {
        _newClientPhoneController.text = last10(phone);
        _phoneError = Validators.validatePhoneNumber(_newClientPhoneController.text);
      } else if (mobile.isNotEmpty) {
        _newClientPhoneController.text = last10(mobile);
        _phoneError = Validators.validatePhoneNumber(_newClientPhoneController.text);
      }
      _newClientMobileController.text = mobile.isNotEmpty ? last10(mobile) : '';
      _ownerGstController.text = (owner['GST Number'] ?? '').toString();
    });
  }

  List<TypeaheadOption> _filterCatalogValues(Iterable<String> values, String query) {
    final unique = values.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? unique
        : unique.where((item) => item.toLowerCase().contains(q)).toList();
    return filtered.map((item) => TypeaheadOption(label: item)).toList();
  }

  void _applySelectedTyre(Map<String, dynamic> tyre) {
    setState(() {
      final brand = (tyre['brand'] ?? '').toString().trim();
      final model = (tyre['model'] ?? '').toString().trim();
      final size = (tyre['size'] ?? '').toString().trim();
      final liSi = (tyre['li_si'] ?? '').toString().trim();

      if (brand.isNotEmpty) _tyreBrandController.text = brand;
      if (model.isNotEmpty) _tyreModelController.text = model;
      if (size.isNotEmpty && size != '-') {
        _tyreSizeController.text = size;
      } else {
        _tyreSizeController.clear();
      }
      if (liSi.isNotEmpty) _tyreLiSiController.text = liSi;

      final billingPrice = tyre['billing_price'] != null
          ? double.tryParse(tyre['billing_price'].toString())
          : null;
      final basicPrice = tyre['basic_price'] != null
          ? double.tryParse(tyre['basic_price'].toString())
          : null;
      final price = billingPrice ?? basicPrice;
      if (price != null) {
        _tyrePriceController.text = price.toStringAsFixed(2);
      }

      _syncTyreComplaint();
    });

    final sizeText = _tyreSizeController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected: ${_tyreBrandController.text} ${_tyreModelController.text}${sizeText.isNotEmpty ? " ($sizeText)" : ""}'),
        backgroundColor: AppTheme.primaryColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openTyreCatalogPicker({bool forCourier = false}) async {
    if (_tyreCatalog.isEmpty) {
      await _fetchTyreCatalog();
    }
    if (!mounted) return;

    final selected = await TyreCatalogPicker.show(
      context,
      tyreCatalog: _tyreCatalog,
      initialBrand: forCourier ? _courierProductBrand : (_tyreBrandController.text.trim().isNotEmpty ? _tyreBrandController.text.trim() : null),
      initialSize: forCourier ? _courierProductSize : (_tyreSizeController.text.trim().isNotEmpty ? _tyreSizeController.text.trim() : null),
    );

    if (selected != null && mounted) {
      if (forCourier) {
        setState(() {
          _courierCategory = 'Tyre';
          _courierProductBrand = (selected['brand'] ?? '').toString().trim();
          _courierProductModel = (selected['model'] ?? '').toString().trim();
          _courierProductSize = (selected['size'] ?? '').toString().trim();

          final billingPrice = selected['billing_price'] != null
              ? double.tryParse(selected['billing_price'].toString())
              : null;
          final basicPrice = selected['basic_price'] != null
              ? double.tryParse(selected['basic_price'].toString())
              : null;
          final price = billingPrice ?? basicPrice;
          if (price != null) {
            _courierProductPriceController.text = price.toStringAsFixed(2);
          }
        });
      } else {
        _applySelectedTyre(selected);
      }
    }
  }

  void _matchAndAutofillTyreDetails() {
    final brand = _tyreBrandController.text.trim().toLowerCase();
    final model = _tyreModelController.text.trim().toLowerCase();
    final size = _tyreSizeController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (brand.isEmpty && size.isEmpty) return;

    final matches = _tyreCatalog.where((t) {
      final tBrand = TyreCatalogHelper.extractBrand(t).toLowerCase();
      final tModel = TyreCatalogHelper.extractModel(t).toLowerCase();
      final tSize = TyreCatalogHelper.extractSize(t).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      bool matchBrand = brand.isEmpty || tBrand == brand;
      bool matchModel = model.isEmpty || tModel == model;
      bool matchSize = size.isEmpty || tSize == size;

      return matchBrand && matchModel && matchSize;
    }).toList();

    if (matches.isNotEmpty) {
      final first = matches.first;
      if (_tyreLiSiController.text.trim().isEmpty && first['li_si'] != null) {
        final liSiStr = first['li_si'].toString().trim();
        if (liSiStr.isNotEmpty) {
          _tyreLiSiController.text = liSiStr;
        }
      }
      final billingPrice = first['billing_price'] != null
          ? double.tryParse(first['billing_price'].toString())
          : null;
      final basicPrice = first['basic_price'] != null
          ? double.tryParse(first['basic_price'].toString())
          : null;
      final price = billingPrice ?? basicPrice;
      if (price != null && (_tyrePriceController.text.trim().isEmpty || _tyrePriceController.text == '0')) {
        _tyrePriceController.text = price.toStringAsFixed(2);
      }
    }
    _syncTyreComplaint();
  }

  void _matchAndAutofillAlloyDetails() {
    final brand = _alloyBrandController.text.trim().toLowerCase();
    final model = _alloyModelController.text.trim().toLowerCase();
    final size = _alloySizeController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (brand.isEmpty && size.isEmpty && model.isEmpty) return;

    final matches = _alloyCatalog.where((t) {
      final tBrand = AlloyCatalogHelper.extractBrand(t).toLowerCase();
      final tModel = AlloyCatalogHelper.extractModel(t).toLowerCase();
      final tSize = AlloyCatalogHelper.extractSize(t).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      bool matchBrand = brand.isEmpty || tBrand == brand;
      bool matchModel = model.isEmpty || tModel == model;
      bool matchSize = size.isEmpty || tSize == size;

      return matchBrand && matchModel && matchSize;
    }).toList();

    if (matches.isNotEmpty) {
      final first = matches.first;
      final price = AlloyCatalogHelper.extractPrice(first);
      if (price != null && (_alloyPriceController.text.trim().isEmpty || _alloyPriceController.text == '0')) {
        _alloyPriceController.text = price.toStringAsFixed(2);
      }
    }
    _syncAlloyComplaint();
  }

  Future<void> _openAlloyCatalogPicker({bool forCourier = false}) async {
    if (_alloyCatalog.isEmpty) {
      await _fetchAlloyCatalog();
    }
    if (!mounted) return;

    final selected = await AlloyCatalogPicker.show(
      context,
      alloyCatalog: _alloyCatalog,
      initialBrand: forCourier ? _courierProductBrand : (_alloyBrandController.text.trim().isNotEmpty ? _alloyBrandController.text.trim() : null),
      initialSize: forCourier ? _courierProductSize : (_alloySizeController.text.trim().isNotEmpty ? _alloySizeController.text.trim() : null),
    );

    if (selected != null && mounted) {
      if (forCourier) {
        setState(() {
          _courierCategory = 'Alloy';
          _courierProductBrand = (selected['brand'] ?? '').toString().trim();
          _courierProductModel = (selected['model'] ?? '').toString().trim();
          _courierProductSize = (selected['size'] ?? '').toString().trim();

          final price = selected['selling_price'] ?? selected['billing_price'];
          if (price != null) {
            final numPrice = double.tryParse(price.toString());
            _courierProductPriceController.text = numPrice != null ? numPrice.toStringAsFixed(2) : price.toString();
          }
        });
      } else {
        setState(() {
          final brand = (selected['brand'] ?? '').toString().trim();
          final model = (selected['model'] ?? '').toString().trim();
          final size = (selected['size'] ?? '').toString().trim();
          final price = selected['selling_price'] ?? selected['billing_price'];

          if (brand.isNotEmpty) _alloyBrandController.text = brand;
          if (model.isNotEmpty) _alloyModelController.text = model;
          if (size.isNotEmpty) _alloySizeController.text = size;
          if (price != null) {
            final numP = double.tryParse(price.toString());
            _alloyPriceController.text = numP != null ? numP.toStringAsFixed(2) : price.toString();
          }
          _syncAlloyComplaint();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected Alloy: ${_alloyBrandController.text} ${_alloyModelController.text} (${_alloySizeController.text})'),
            backgroundColor: const Color(0xFF0D9488),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    _complaintFocusNode.dispose();
    _vehicleNumberController.dispose();
    _mobileSearchController.dispose();
    _newVehicleNameController.dispose();
    _newColorController.dispose();
    _newOdometerController.dispose();
    _newClientNameController.dispose();
    _newClientPhoneController.dispose();
    _newClientMobileController.dispose();
    _odometerController.dispose();
    _complaintInputController.dispose();
    _complaintAmountController.dispose();
    _complaintCountController.dispose();
    _laborCostController.dispose();
    _ownerGstController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    
    for (var controller in _tyreQRControllers.values) {
      controller.dispose();
    }
    for (var controller in _tyreSpecControllers.values) {
      controller.dispose();
    }
    
    _tyreBrandController.dispose();
    _tyreModelController.dispose();
    _tyreSizeController.dispose();
    _tyreLiSiController.dispose();
    _tyreCountController.dispose();
    _tyrePriceController.dispose();
    _tyreTotalController.dispose();

    _alloyBrandController.dispose();
    _alloyModelController.dispose();
    _alloySizeController.dispose();
    _alloyCountController.dispose();
    _alloyPriceController.dispose();
    _alloyTotalController.dispose();
    super.dispose();
  }

  void _syncTyreComplaint() {
    int count = int.tryParse(_tyreCountController.text) ?? 0;
    double price = double.tryParse(_tyrePriceController.text) ?? 0.0;
    _tyreTotalController.text = (count * price).toStringAsFixed(2);
  }

  void _syncAlloyComplaint() {
    int count = int.tryParse(_alloyCountController.text) ?? 0;
    double price = double.tryParse(_alloyPriceController.text) ?? 0.0;
    _alloyTotalController.text = (count * price).toStringAsFixed(2);
  }

  // --- GOOGLE DRIVE REMOVED ---

  // --- DATA FETCHING & LOGIC ---

  void _resetScreen() {
    setState(() {
      _vehicleNumberController.clear();
      _mobileSearchController.clear();
      _mobileSearchError = null;
      _vehicleDetails = null;
      _showCreateVehicleForm = false;
      _isVehicleJobCardDraft = false;
      _loadedRegistrationDraftId = null;
      _complaints.clear();
      _currentVehicleId = null;
      _searchError = null;
      _isFoundInTally = false;
      _newVehicleNameController.clear();
      _newColorController.clear();
      _newOdometerController.clear();
      _selectedOwnerId = null;
      _newClientNameController.clear();
      _newClientPhoneController.clear();
      _newClientMobileController.clear();
      _odometerController.clear();
      _complaintInputController.clear();
      _complaintAmountController.clear();
      _complaintCountController.text = '1';
      _laborCostController.clear();
      _tyreBrandController.clear();
      _tyreModelController.clear();
      _tyreSizeController.clear();
      _tyreLiSiController.clear();
      _tyreCountController.text = '1';
      _tyrePriceController.clear();
      _tyreTotalController.clear();
      _showAlloySection = false;
      _alloyBrandController.clear();
      _alloyModelController.clear();
      _alloySizeController.clear();
      _alloyCountController.text = '4';
      _alloyPriceController.clear();
      _alloyTotalController.clear();
      _selectedBrand = null;
      _selectedModelId = null;
      _selectedModelName = null;
      _wheelPhotos.clear();
      _vehiclePhotos.clear();
      for (String wheel in _requiredWheels) {
        _tyreQRControllers[wheel]?.clear();
        _tyreSpecControllers[wheel]?.clear();
      }
      _tyreQRImages.clear();
      _audioPath = null;
      _isRecording = false;
      _damageMarks.clear();
      _clientNameDiffers = false;
      _clientPhoneDiffers = false;
      _isBuyback = false;
      _ownerDetails = null;
      _ownerGstController.clear();

      // ✅ Clear validation errors
      _vehicleNumberError = null;
      _phoneError = null;
      _odometerError = null;
    });
  }

  Future<void> _fetchVehicleModels() async {
    try {
      final response =
          await supabase.from('vehicle_models').select('id, brand, "Model name"');
      if (mounted) {
        setState(() {
          _vehicleModelsCache = List<Map<String, dynamic>>.from(response);
          _uniqueBrands = _vehicleModelsCache
              .map<String>((e) => e['brand'] as String)
              .toSet()
              .toList()
            ..sort();
        });
      }
    } catch (e) {
      _showErrorSnackBar(AppConstants.errorUnknown); // ✅ Use constant
    }
  }

  void _applyFoundVehicle(Map<String, dynamic> response, {bool isFromTally = false}) {
    final latestOdometer = response['latest_odometer'];
    final latestClientName = response['latest_client_name'];
    final latestClientPhone = response['latest_client_phone'];
    final ownerDetails = response['owner_details'];
    final vehicleNumber = response['Vehicle Number']?.toString() ?? '';

    if (kDebugMode) {
      print('🔍 Applying vehicle: $vehicleNumber (from_tally: $isFromTally)');
      print('👤 Owner details: $ownerDetails');
      print('📱 Latest client phone: $latestClientPhone');
    }

    setState(() {
      _vehicleNumberController.text = vehicleNumber;
      _isFoundInTally = isFromTally;
      _vehicleDetails = isFromTally ? null : response;
      _currentVehicleId = response['id'];
      _lastKnownOdometer = latestOdometer is int ? latestOdometer : int.tryParse(latestOdometer?.toString() ?? '');
      _ownerDetails = ownerDetails;
      _selectedOwnerId = ownerDetails?['id']?.toString() ?? response['owner_id']?.toString();

      // Populate controllers with the LATEST info
      _newClientNameController.text = ownerDetails?['Owner name'] ?? latestClientName ?? '';
      _newClientPhoneController.text = ownerDetails?['PhoneNumber'] ?? latestClientPhone ?? '';
      _newClientMobileController.text = ownerDetails?['MobileNumber'] ?? '';
      _odometerController.text = latestOdometer?.toString() ?? '';
      _newOdometerController.text = latestOdometer?.toString() ?? '';
      _ownerGstController.text = ownerDetails?['GST Number'] ?? '';

      if (isFromTally) {
        _showCreateVehicleForm = true; // Show pre-filled create vehicle form
        final detectedModel = (response['detected_model'] ?? '').toString().trim();
        if (detectedModel.isNotEmpty) {
          _matchAndSelectVehicleModel(detectedModel);
        }
      } else {
        // Compare latest details with original vehicle record details
        final originalName = (response['Owner name'] ?? '').toString().trim();
        final originalPhone = (response['MobileNumber'] ?? '').toString().trim();

        _clientNameDiffers = originalName.isNotEmpty &&
            latestClientName != null &&
            latestClientName.toString().trim().isNotEmpty &&
            latestClientName.toString().trim().toLowerCase() != originalName.toLowerCase();

        _clientPhoneDiffers = originalPhone.isNotEmpty &&
            latestClientPhone != null &&
            latestClientPhone.toString().trim().isNotEmpty &&
            latestClientPhone.toString().trim() != originalPhone;

        _showCreateVehicleForm = false; // Vehicle already registered
      }
    });

    if (isFromTally && mounted) {
      final ledgerName = response['tally_ledger_name'] ?? 'Tally';
      final modelTxt = (response['detected_model'] ?? '').toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found in Tally ($ledgerName${modelTxt.isNotEmpty ? ' • $modelTxt' : ''})! Details pre-filled.'),
          backgroundColor: const Color(0xFF0D9488),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _searchVehicle() async {
    final rawVehicleNumber = _vehicleNumberController.text.trim();
    final normalizedVehicleNumber = VehicleNumberUtils.normalize(rawVehicleNumber);

    if (normalizedVehicleNumber.isNotEmpty &&
        _vehicleNumberController.text.trim() != normalizedVehicleNumber) {
      _vehicleNumberController.text = normalizedVehicleNumber;
      _vehicleNumberController.selection = TextSelection.fromPosition(
        TextPosition(offset: _vehicleNumberController.text.length),
      );
    }

    // ✅ Validate vehicle number
    final validationError = Validators.validateVehicleNumber(normalizedVehicleNumber);
    if (validationError != null) {
      setState(() => _vehicleNumberError = validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _searchError = null;
      _vehicleNumberError = null;
      _vehicleDetails = null;
      _showCreateVehicleForm = false;
    });

    try {
      // ✅ Use the updated service method
      final response = await SupabaseService().searchVehicle(normalizedVehicleNumber);

      if (response == null) {
        setState(() {
          _isFoundInTally = false;
          _vehicleDetails = null;
          _showCreateVehicleForm = true; // Vehicle not found, show create form
          _newOdometerController.clear();
          // Clear potential diff flags
          _clientNameDiffers = false;
          _clientPhoneDiffers = false;
          _ownerDetails = null;
        });
      } else {
        final isFromTally = response['from_tally'] == true;
        _applyFoundVehicle(response, isFromTally: isFromTally);
      }
    } catch (error) {
      setState(() {
        _vehicleDetails = null;
        _showCreateVehicleForm = true; // Assume error means not found
        _clientNameDiffers = false;
        _clientPhoneDiffers = false;
        _searchError = 'Error searching vehicle.'; // Provide generic error
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchByMobileNumber() async {
    final rawMobile = _mobileSearchController.text.trim();
    final digitsOnly = rawMobile.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.length != 10) {
      setState(() => _mobileSearchError = 'Please enter a valid 10-digit mobile number');
      return;
    }

    setState(() {
      _isLoading = true;
      _searchError = null;
      _mobileSearchError = null;
      _vehicleNumberError = null;
      _vehicleDetails = null;
      _showCreateVehicleForm = false;
    });

    try {
      final vehicles = await SupabaseService().searchVehiclesByMobileNumber(digitsOnly);

      if (!mounted) return;

      if (vehicles.isEmpty) {
        // Check if owner master has this customer registered without a vehicle
        final owner = await SupabaseService().searchOwnerByMobileNumber(digitsOnly);

        setState(() {
          _isFoundInTally = false;
          _vehicleDetails = null;
          _showCreateVehicleForm = true; // Vehicle not found, show create form
          _currentVehicleId = null;
          _lastKnownOdometer = null;
          _vehicleNumberController.clear(); // Ready for new vehicle number input
          _newOdometerController.clear();
          _clientNameDiffers = false;
          _clientPhoneDiffers = false;
          _ownerDetails = owner;

          // Pre-populate mobile and owner info
          _newClientPhoneController.text = digitsOnly;
          _newClientMobileController.text = digitsOnly;
          if (owner != null) {
            _selectedOwnerId = owner['id']?.toString();
            _newClientNameController.text = (owner['Owner name'] ?? '').toString();
            _ownerGstController.text = (owner['GST Number'] ?? '').toString();
          } else {
            _selectedOwnerId = null;
            _newClientNameController.clear();
            _ownerGstController.clear();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              owner != null
                  ? 'Customer found (${owner['Owner name']}) with no vehicle. Please enter vehicle details below.'
                  : 'No vehicle found for mobile $digitsOnly. Please register new vehicle below.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (vehicles.length == 1) {
        _applyFoundVehicle(vehicles.first);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vehicle found for $digitsOnly!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // Multiple vehicles found for this mobile number
        _showVehicleSelectionModal(vehicles, digitsOnly);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _vehicleDetails = null;
          _showCreateVehicleForm = true;
          _searchError = 'Error searching vehicle by mobile: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVehicleSelectionModal(List<Map<String, dynamic>> vehicles, String mobileNumber) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${vehicles.length} Vehicles Found',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Linked to mobile $mobileNumber',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Select vehicle to create job card:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final v = vehicles[index];
                    final vehNum = (v['Vehicle Number'] ?? 'Unknown').toString();
                    final brand = v['vehicle_models']?['brand'] ?? '';
                    final model = v['vehicle_models']?['Model name'] ?? '';
                    final odo = v['latest_odometer'] ?? v['odometer'];
                    final owner = v['owner_details']?['Owner name'] ?? v['Owner name'] ?? '';

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _applyFoundVehicle(v);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                vehNum,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    brand.isNotEmpty || model.isNotEmpty
                                        ? '$brand $model'.trim()
                                        : 'Model not set',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  if (owner.isNotEmpty)
                                    Text(
                                      owner,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  if (odo != null)
                                    Text(
                                      'Last Odo: $odo km',
                                      style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final firstOwner = vehicles.first['owner_details'] ?? {};
                    setState(() {
                      _isFoundInTally = false;
                      _vehicleDetails = null;
                      _showCreateVehicleForm = true;
                      _currentVehicleId = null;
                      _lastKnownOdometer = null;
                      _vehicleNumberController.clear();
                      _newOdometerController.clear();
                      _clientNameDiffers = false;
                      _clientPhoneDiffers = false;
                      _newClientPhoneController.text = mobileNumber;
                      _newClientMobileController.text = mobileNumber;
                      _newClientNameController.text = firstOwner['Owner name'] ?? vehicles.first['Owner name'] ?? '';
                      _selectedOwnerId = firstOwner['id']?.toString() ?? vehicles.first['owner_id']?.toString();
                      _ownerGstController.text = firstOwner['GST Number'] ?? '';
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Register Another Vehicle for this Mobile'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _matchAndSelectVehicleModel(String detectedModel) {
    if (detectedModel.isEmpty || _vehicleModelsCache.isEmpty) return;

    final query = detectedModel.toLowerCase().trim();

    Map<String, dynamic>? exactMatch;
    Map<String, dynamic>? partialMatch;

    for (final m in _vehicleModelsCache) {
      final brand = (m['brand'] ?? '').toString().toLowerCase().trim();
      final model = (m['Model name'] ?? '').toString().toLowerCase().trim();
      final full = '$brand $model'.toLowerCase();

      if (full == query || model == query) {
        exactMatch = m;
        break;
      }

      if (query.contains(model) && model.length >= 2) {
        partialMatch ??= m;
      } else if (query.contains(brand) && brand.length >= 3) {
        partialMatch ??= m;
      }
    }

    final selected = exactMatch ?? partialMatch;
    if (selected != null) {
      setState(() {
        _selectedBrand = selected['brand'] as String?;
        _selectedModelId = selected['id'] as int?;
        _selectedModelName = selected['Model name'] as String?;
      });
    }
  }

  Future<void> _createVehicle() async {
    if (_isSaving || _isLoading) return;
    _isSaving = true;

    final adminSettings = Provider.of<AdminSettingsProvider>(context, listen: false);
    
    // ✅ Validate all required fields
    final vehicleNum = VehicleNumberUtils.normalize(_vehicleNumberController.text.trim());
    final vehicleNumError = Validators.validateVehicleNumber(vehicleNum);
    final phoneError =
        Validators.validatePhoneNumber(_newClientPhoneController.text.trim());
    final rawOdo = _newOdometerController.text.trim();
    final odometerError = rawOdo.isEmpty
        ? 'Odometer reading is required'
        : Validators.validateOdometer(rawOdo);

    if (vehicleNum.isEmpty ||
        vehicleNumError != null ||
        _newClientNameController.text.trim().isEmpty ||
        phoneError != null ||
        rawOdo.isEmpty ||
        odometerError != null ||
        _selectedBrand == null ||
        _selectedModelId == null) {
      setState(() {
        _vehicleNumberError = vehicleNumError ?? (vehicleNum.isEmpty ? 'Vehicle number required' : null);
        _phoneError = phoneError;
        _odometerError = odometerError;
      });

      _isSaving = false;
      _showErrorSnackBar(rawOdo.isEmpty ? 'Odometer reading is required.' : AppConstants.errorInvalidInput); // ✅ Use constant
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get the model name from the selected model
      final selectedModel = _vehicleModelsCache.firstWhere(
        (model) => model['id'] == _selectedModelId,
        orElse: () => {},
      );
      final modelName = selectedModel['Model name'] as String?;

      // First, save owner details to owner_master table
      final ownerData = {
        'Owner name': _newClientNameController.text.trim(),
        'PhoneNumber': _newClientPhoneController.text.trim(), // Client Phone -> PhoneNumber
        'MobileNumber': _newClientMobileController.text.trim().isEmpty ? null : _newClientMobileController.text.trim(), // Client Mobile -> MobileNumber
        'GST Number': _ownerGstController.text.trim(),
      };
      
      final ownerId = _selectedOwnerId ??
          await vehicleService.createOrUpdateOwner(context, ownerData);

      final vehicleData = {
        'Vehicle Number': VehicleNumberUtils.normalize(_vehicleNumberController.text.trim()),
        'vehicle_name': null,
        'model_id': _selectedModelId,
        'Model name': modelName,
        'odometer': int.tryParse(_newOdometerController.text.trim()) ?? 0,
        'Owner name': _newClientNameController.text.trim(),
        'MobileNumber': _newClientMobileController.text.trim().isEmpty ? _newClientPhoneController.text.trim() : _newClientMobileController.text.trim(), // Use mobile if available, otherwise phone
        'owner_id': ownerId, // Link to owner_master table
      };
      
      await vehicleService.createOrUpdateVehicle(context, vehicleData);

      _showSuccessSnackBar(AppConstants.successSaved); // ✅ Use constant
      await _searchVehicle();
    } catch (error) {
      _showErrorSnackBar('Failed to create vehicle: ${error.toString()}');
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _ensureBranchPrefixConfigured() async {
    final companyService = CompanyService();
    if (!companyService.hasActiveCompany) {
      await companyService.loadPersistedCompany();
    }

    if (companyService.hasBranchPrefix) {
      return true;
    }

    if (!mounted) return false;

    final user = Provider.of<UserProvider>(context, listen: false).user;
    final role = user?['role']?.toString();
    final isAdminOrSuperAdmin = role == AppConstants.roleAdmin || role == AppConstants.roleSuperAdmin;
    final bName = companyService.branchName ?? 'Active Branch';

    if (isAdminOrSuperAdmin) {
      final prefixController = TextEditingController();
      final formKey = GlobalKey<FormState>();

      final enteredPrefix = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF4F46E5), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Set Branch Prefix',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Branch "$bName" does not have a Job Card format prefix set. You must configure a prefix (e.g. TYX or TVR) before creating job cards for this branch.',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: prefixController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Branch Prefix *',
                    hintText: 'e.g. TYX, TVR, KCH',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Prefix is required';
                    if (v.trim().length < 2) return 'Prefix must be at least 2 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: prefixController,
                  builder: (context, value, _) {
                    final clean = value.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                    return Text(
                      'Preview: ${clean.isEmpty ? "PREFIX" : clean}${DateTime.now().year}001',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, prefixController.text.trim().toUpperCase());
                }
              },
              child: const Text('Save & Continue'),
            ),
          ],
        ),
      );

      if (enteredPrefix != null && enteredPrefix.isNotEmpty) {
        final bId = companyService.branchId;
        if (bId != null) {
          await companyService.setBranchPrefix(bId, enteredPrefix);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Branch prefix set to "$enteredPrefix"'), backgroundColor: Colors.green),
            );
          }
          return true;
        }
      }
      return false;
    } else {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Branch Prefix Required'),
            ],
          ),
          content: Text(
            'Cannot create job card for branch "$bName" because no Job Card Prefix has been configured.\n\nPlease contact your administrator to set the prefix for this branch in Branch Settings.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  Future<void> _saveVehicleRegistrationDraft() async {
    if (_isSaving || _isLoading) return;
    _isSaving = true;
    setState(() => _isLoading = true);

    try {
      final vehicleNo = VehicleNumberUtils.normalize(_vehicleNumberController.text.trim());
      if (vehicleNo.isEmpty) {
        _showErrorSnackBar('Please enter a vehicle number to save a draft.');
        return;
      }

      final isFeatureEnabled = await ClientFeaturesService().checkFeatureStatus('jobcards');
      if (!isFeatureEnabled) {
        _showErrorSnackBar('Service Restricted: Creating Job Cards is currently unavailable. Please contact support.');
        return;
      }

      if (!await _ensureBranchPrefixConfigured()) {
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (!CompanyService().hasActiveCompany) {
        await CompanyService().loadPersistedCompany();
      }
      final String? companyGuid = CompanyService().guid;

      final int? odoReading = int.tryParse(_newOdometerController.text.trim().isNotEmpty
          ? _newOdometerController.text.trim()
          : _odometerController.text.trim());

      final draftData = {
        'status': AppConstants.statusDraft,
        'vehicle_id': _currentVehicleId,
        'Owner name': _newClientNameController.text.trim().isNotEmpty ? _newClientNameController.text.trim() : null,
        'client_phone': _newClientPhoneController.text.trim().isNotEmpty ? _newClientPhoneController.text.trim() : null,
        'odometer_reading': odoReading,
        'complaint': jsonEncode(_complaints),
        'company_id': CompanyService().companyId,
        'company_name': CompanyService().companyName,
        'Guid': companyGuid,
        'marks': jsonEncode({
          'is_vehicle_registration_draft': true,
          'vehicle_number': vehicleNo,
          'client_mobile': _newClientMobileController.text.trim(),
          'gst_no': _ownerGstController.text.trim(),
          'brand': _selectedBrand,
          'model_id': _selectedModelId,
          'model_name': _selectedModelName,
          'is_buyback': _isBuyback,
        }),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'executive_id': user?['id'],
      };

      final dynamic targetDraftId = widget.draftJob != null ? widget.draftJob!['id'] : _loadedRegistrationDraftId;
      if (targetDraftId != null) {
        draftData.remove('created_at');
        final dataWithCompany = CompanyService().addCompanyFields(draftData, tableName: 'reports');
        await supabase.from('reports').update(dataWithCompany).eq('id', targetDraftId);
      } else {
        draftData['job_card_id'] = await CompanyService().generateJobCardId();
        final dataWithCompany = CompanyService().addCompanyFields(draftData, tableName: 'reports');
        await supabase.from('reports').insert(dataWithCompany);
      }

      if (!mounted) return;
      final String formattedNow = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vehicle registration draft saved on $formattedNow!'),
          backgroundColor: Colors.purple,
        ),
      );

      _resetScreen();
    } catch (e) {
      _showErrorSnackBar('Failed to save draft: $e');
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFullPageRegistrationDrafts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedRegistrationDraftsScreen(
          onSelectDraft: (draft) {
            _loadDraftIntoForm(draft);
          },
        ),
      ),
    );
  }

  void _loadDraftIntoForm(Map<String, dynamic> draft, {bool showSnackBar = true}) {
    setState(() {
      Map<String, dynamic> marks = {};
      if (draft['marks'] is String) {
        try { marks = jsonDecode(draft['marks']); } catch (_) {}
      } else if (draft['marks'] is Map) {
        marks = Map<String, dynamic>.from(draft['marks']);
      }

      int? vehId;
      if (draft['vehicle_id'] != null) {
        vehId = draft['vehicle_id'] is int ? draft['vehicle_id'] as int : int.tryParse(draft['vehicle_id'].toString());
      }
      if (vehId == null && draft['vehicles'] is Map && draft['vehicles']['id'] != null) {
        vehId = draft['vehicles']['id'] is int ? draft['vehicles']['id'] as int : int.tryParse(draft['vehicles']['id'].toString());
      }
      _currentVehicleId = vehId;

      final String vehNo = marks['vehicle_number'] ?? draft['Vehicle Number'] ?? draft['vehicles']?['Vehicle Number'] ?? '';
      _vehicleNumberController.text = vehNo;
      _newClientNameController.text = draft['Owner name'] ?? '';
      _newClientPhoneController.text = draft['client_phone'] ?? '';
      _newClientMobileController.text = marks['client_mobile'] ?? draft['client_mobile'] ?? '';
      _ownerGstController.text = marks['gst_no'] ?? draft['gst_no'] ?? '';
      _newOdometerController.text = draft['odometer_reading']?.toString() ?? '';
      _isBuyback = marks['is_buyback'] == true || draft['is_buyback'] == true;
      
      _selectedBrand = marks['brand'] as String?;
      _selectedModelId = int.tryParse(marks['model_id']?.toString() ?? '');
      _selectedModelName = marks['model_name'] as String?;

      _selectedGlobalTyreBrand = marks['tyre_brand'] as String?;
      _selectedGlobalTyreModel = marks['tyre_model'] as String?;
      _selectedGlobalTyreSize = marks['tyre_size'] as String?;
      _selectedGlobalTyreLiSi = marks['tyre_li_si'] as String?;

      _loadedRegistrationDraftId = draft['id'];
      final bool isRegistrationDraft = marks['is_vehicle_registration_draft'] == true;

      if (isRegistrationDraft) {
        // Vehicle Registration Draft: Show vehicle registration form prefilled (vehicle not in DB yet)
        _isVehicleJobCardDraft = false;
        _showCreateVehicleForm = true;
        _vehicleDetails = null;
      } else {
        // Real Job Card Draft: Show green Vehicle Found banner and complaints section
        _isVehicleJobCardDraft = true;
        _showCreateVehicleForm = false;
        if (draft['vehicles'] is Map) {
          _vehicleDetails = Map<String, dynamic>.from(draft['vehicles']);
        } else {
          _vehicleDetails = {
            'Vehicle Number': vehNo,
            'Owner name': draft['Owner name'] ?? '',
            'client_phone': draft['client_phone'] ?? '',
            'Guid': draft['Guid'],
          };
        }

        if (_currentVehicleId == null && vehNo.isNotEmpty) {
          SupabaseService().searchVehicle(vehNo).then((resp) {
            if (resp != null && mounted) {
              setState(() {
                _currentVehicleId = resp['id'];
                _vehicleDetails = resp;
              });
            }
          });
        }
      }

      final rawComplaints = draft['complaint'];
      _complaints.clear();
      if (rawComplaints is List) {
        _complaints.addAll(List<Map<String, dynamic>>.from(rawComplaints.map((e) => Map<String, dynamic>.from(e))));
      } else if (rawComplaints is String && rawComplaints.startsWith('[')) {
        try {
          final decoded = jsonDecode(rawComplaints) as List;
          _complaints.addAll(List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e))));
        } catch (_) {}
      }

      // If it's an Edit Requested job or completed job, items might be in 'approved' or 'suggested'
      if (_complaints.isEmpty) {
        _complaints.clear();
        final rawApproved = draft['approved'];
        if (rawApproved is List) {
          _complaints.addAll(List<Map<String, dynamic>>.from(rawApproved.map((e) => Map<String, dynamic>.from(e))));
        } else if (rawApproved is String && rawApproved.startsWith('[')) {
          try {
            final decoded = jsonDecode(rawApproved) as List;
            _complaints.addAll(List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e))));
          } catch (_) {}
        }

        final rawSuggested = draft['suggested'];
        if (rawSuggested is List) {
          _complaints.addAll(List<Map<String, dynamic>>.from(rawSuggested.map((e) => Map<String, dynamic>.from(e))));
        } else if (rawSuggested is String && rawSuggested.startsWith('[')) {
          try {
            final decoded = jsonDecode(rawSuggested) as List;
            _complaints.addAll(List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e))));
          } catch (_) {}
        }
        
        // Ensure no duplicates by text (in case it got added twice)
        final seenTexts = <String>{};
        _complaints.retainWhere((c) {
          final txt = c['text'] as String?;
          if (txt == null || seenTexts.contains(txt)) return false;
          seenTexts.add(txt);
          return true;
        });
      }

      final rawAssignments = draft['technician_assignments'];
      _technicianAssignments.clear();
      if (rawAssignments is List) {
        _technicianAssignments.addAll(List<Map<String, dynamic>>.from(rawAssignments.map((e) => Map<String, dynamic>.from(e))));
      } else if (rawAssignments is String && rawAssignments.trim().startsWith('[')) {
        try {
          final decoded = jsonDecode(rawAssignments) as List;
          _technicianAssignments.addAll(List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e))));
        } catch (_) {}
      }


    });

    if (showSnackBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded draft for ${_vehicleNumberController.text}'),
            backgroundColor: Colors.green,
          ),
        );
      });
    }
  }

  Future<void> _saveJobCard({bool isDraft = false}) async {
    if (_isSaving || _isLoading) return;
    _isSaving = true;
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (_complaints.isEmpty) {
        _showErrorSnackBar('Please add at least one complaint.');
        _isSaving = false;
        setState(() => _isLoading = false);
        return;
      }

      final odoReading = _newOdometerController.text.trim().isNotEmpty
          ? _newOdometerController.text.trim()
          : _odometerController.text.trim();
      if (odoReading.isEmpty) {
        _showErrorSnackBar('Odometer reading is required.');
        setState(() {
          _odometerError = 'Odometer reading is required';
          _isLoading = false;
        });
        _isSaving = false;
        return;
      }

      final isFeatureEnabled = await ClientFeaturesService().checkFeatureStatus('jobcards');
      if (!isFeatureEnabled) {
        _showErrorSnackBar('Service Restricted: Creating Job Cards is currently unavailable. Please contact support.');
        return;
      }

      if (!mounted) return;
      final user = userProvider.user;
      if (_currentVehicleId == null || user == null) {
        _showErrorSnackBar('No vehicle selected or user not logged in.');
        return;
      }

      if (!await _ensureBranchPrefixConfigured()) {
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isDraft ? 'Saving as draft...' : ((widget.draftJob != null && widget.draftJob?['status'] != AppConstants.statusDraft) ? 'Saving updates...' : 'Creating job card...'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Checking duplicates & saving details...'),
              ],
            ),
          );
        },
      );

      try {
        // ✅ Skip duplicate check entirely when updating an existing draft
        if (widget.draftJob != null) {
          await _executeSaveJobCard(isDraft: isDraft);
          return;
        }

        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day).toIso8601String();
        final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();

        final existingReports = await supabase
            .from('reports')
            .select('id, executive:executive_id(username)')
            .eq('vehicle_id', _currentVehicleId!)
            .gte('created_at', startOfDay)
            .lte('created_at', endOfDay);

        if (!mounted) return;
        if (existingReports.isNotEmpty) {
          Navigator.of(context).pop(); // Temporarily hide progress dialog
          
          final executiveName = existingReports.first['executive']?['username'] ??
              'another executive';
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Duplicate Job Card Warning'),
              content: Text(
                  'A job card for this vehicle was already created today by $executiveName. Are you sure you want to create another one?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm & Proceed'),
                ),
              ],
            ),
          );
          if (!mounted || confirmed != true) {
            return;
          }
          
          // Re-show progress dialog if confirmed
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isDraft ? 'Saving as draft...' : 'Creating job card...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Uploading images and saving details...'),
                  ],
                ),
              );
            },
          );
        }

        await _executeSaveJobCard(isDraft: isDraft);
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        _showErrorSnackBar('Error checking for duplicates: $e');
      }
    } finally {
      _isSaving = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _executeSaveJobCard({bool isDraft = false}) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isLoading = false);
      }
      _showErrorSnackBar('You are not logged in.');
      return;
    }

    if (!kIsWeb && !isDraft && widget.draftJob?['status'] != AppConstants.statusEditRequested) {
      // ✅ Modify Odometer validation and saving logic (2e)
      // Validate required wheel photos (mandatory on mobile app, optional on web for testing)
      if (_wheelPhotos.length < 5) {
        if (mounted) {
          Navigator.of(context).pop();
          setState(() => _isLoading = false);
        }

        final missingWheels = _requiredWheels.where((w) => !_wheelPhotos.containsKey(w)).join(', ');
        final takePhotos = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Missing Photos'),
            content: Text('Missing required wheel photos: $missingWheels.\nWould you like to take them now?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Take Photos'),
              ),
            ],
          ),
        );

        if (takePhotos == true) {
          await _startRapidCapture();
          if (_wheelPhotos.length >= 5) {
            _showSuccessSnackBar('Photos added! Please click Create Job Card again.');
          }
        }
        return;
      }
    }

    final odoText = _newOdometerController.text.trim().isNotEmpty
        ? _newOdometerController.text.trim()
        : _odometerController.text.trim();
    if (odoText.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() {
          _isLoading = false;
          _isSaving = false;
          _odometerError = 'Odometer reading is required';
        });
      }
      _showErrorSnackBar('Odometer reading is required.');
      return;
    }

    final odometerFormatError = Validators.validateOdometer(odoText);
    if (odometerFormatError != null) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isLoading = false);
      }
      _showErrorSnackBar(odometerFormatError);
      return;
    }

    final newOdometer =
        int.tryParse(odoText) ?? _lastKnownOdometer ?? 0;

    // REMOVE the blocking check:
    // if (newOdometer < (_lastKnownOdometer ?? 0)) {
    //   _showErrorSnackBar('Odometer reading cannot be lower than the last service.');
    //   return;
    // }
    // Remove duplicate dialog since it's now shown in _saveJobCard

    try {
      final marksJson =
          _damageMarks.map((p) => {'x': p.dx, 'y': p.dy}).toList();

      // ✅ FIX: Ensure executiveId is an integer or null
      final int? executiveId = (user['role'] == AppConstants.rolePickupDropoff)
          ? null
          : user['id']; // Directly use the integer ID

      // Only create a new owner record when no existing owner is loaded.
      // For existing vehicles, _ownerDetails is already set from the DB search,
      // so we skip insertion to avoid violating the owner_master unique constraint.
      if (_ownerDetails == null) {
        final ownerData = {
          'Owner name': _newClientNameController.text.trim(),
          'PhoneNumber': _newClientPhoneController.text.trim(),
          'MobileNumber': _newClientMobileController.text.trim().isEmpty ? null : _newClientMobileController.text.trim(),
          'GST Number': _ownerGstController.text.trim(),
        };
        await vehicleService.createOrUpdateOwner(context, ownerData);
      }

      // Ensure branch context is active and valid
      if (!CompanyService().hasActiveCompany) {
        final currentUser = Provider.of<UserProvider>(context, listen: false).user;
        if (currentUser != null) {
          await CompanyService().loadCompaniesForUser(currentUser);
        } else {
          await CompanyService().loadPersistedCompany();
        }
      }
      final String? companyGuid = CompanyService().guid;
      final String? companyName = CompanyService().companyName;
      final String? branchId = CompanyService().branchId;
      final String? branchName = CompanyService().branchName;
      final String branchFmt = CompanyService().branchFormat;
      debugPrint('🔵 JobCard: Saving with Guid=$companyGuid, branch=$branchName (id=$branchId), format=$branchFmt');
      if (companyGuid == null && branchId == null && companyName == null) {
        _showErrorSnackBar('No branch selected. Please select a branch from the top switcher.');
        setState(() => _isLoading = false);
        return;
      }

      // Collect tyre warranty details
      Map<String, Map<String, String>> tyreDetails = {};
      for (String wheel in _requiredWheels) {
        final hasImage = _tyreQRImages[wheel] != null;
        final spec = (_selectedGlobalTyreBrand != null && _selectedGlobalTyreModel != null)
            ? '$_selectedGlobalTyreBrand $_selectedGlobalTyreModel'
            : '';
        if (hasImage) { // Only add if it actually has an image
          tyreDetails[wheel] = {};
          tyreDetails[wheel]!['has_image'] = 'true';
          if (spec.isNotEmpty) tyreDetails[wheel]!['spec'] = spec;
        }
      }
      final String barcodeJson = tyreDetails.isNotEmpty ? jsonEncode(tyreDetails) : '';

      final Map<String, dynamic> marksPayload = {
        ...marksJson.asMap().map((k, v) => MapEntry(k.toString(), v)),
        // Save tyre spec fields so they're restored on draft reopen
        if (_selectedGlobalTyreBrand != null) 'tyre_brand': _selectedGlobalTyreBrand,
        if (_selectedGlobalTyreModel != null) 'tyre_model': _selectedGlobalTyreModel,
        if (_selectedGlobalTyreSize != null) 'tyre_size': _selectedGlobalTyreSize,
        if (_selectedGlobalTyreLiSi != null) 'tyre_li_si': _selectedGlobalTyreLiSi,
        'is_buyback': _isBuyback,
      };

      final Map<String, dynamic> insertData = {
        'vehicle_id': _currentVehicleId,
        'executive_id': executiveId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'complaint': jsonEncode(_complaints),
        if (barcodeJson.isNotEmpty) 'barcode': barcodeJson,
        'status': isDraft ? AppConstants.statusDraft : (
          (widget.draftJob?['status'] == AppConstants.statusEditRequested || widget.draftJob?['status'] == AppConstants.statusCompleted)
              ? AppConstants.statusCompleted 
              : AppConstants.statusWorkInProgress
        ), 
        'started_at': isDraft ? null : (widget.draftJob?['started_at'] ?? DateTime.now().toUtc().toIso8601String()),
        'marks': jsonEncode(marksPayload),
        'odometer_reading': newOdometer,
        'labour_cost': double.tryParse(_laborCostController.text) ?? 0.0,
        'Owner name': _newClientNameController.text.trim(),
        'client_phone': _newClientPhoneController.text.trim(),
        'technician_assignments': _technicianAssignments.isNotEmpty ? jsonEncode(_technicianAssignments) : null,
        'company_id': CompanyService().companyId,
        'branch_id': branchId,
        'branch_name': branchName,
        'Guid': companyGuid,
        'company_name': companyName,
      };

      // Preserve existing photo_urls from draft (don't wipe them on re-save)
      if (widget.draftJob != null) {
        final existingPhotos = widget.draftJob!['photo_urls'];
        if (existingPhotos != null) {
          insertData['photo_urls'] = existingPhotos;
        }
      } else {
        insertData['photo_urls'] = null;
      }

      // Add booking_id if this job card is created from a direct booking
      if (widget.bookingId != null) {
        insertData['booking_id'] = widget.bookingId!;
      }



      int jobId;
      String? jobCardId;

      final dynamic existingDraftId = widget.draftJob != null ? widget.draftJob!['id'] : _loadedRegistrationDraftId;

      if (existingDraftId != null) {
        jobId = existingDraftId is int
            ? existingDraftId
            : int.parse(existingDraftId.toString());
        insertData.remove('created_at');
        // If the draft didn't have a job_card_id yet, generate one
        if (insertData['job_card_id'] == null || insertData['job_card_id'].toString().isEmpty) {
          final existingCardId = widget.draftJob?['job_card_id'];
          if (existingCardId != null && existingCardId.toString().isNotEmpty) {
            jobCardId = existingCardId.toString();
          } else {
            jobCardId = await CompanyService().generateJobCardId(overrideBranchId: insertData['branch_id']?.toString());
            insertData['job_card_id'] = jobCardId;
          }
        }
        await supabase.from('reports').update(insertData).eq('id', jobId);
      } else {
        final inserted = await vehicleService.createReport(context, insertData);
        jobId = inserted['id'] as int;
        jobCardId = inserted['job_card_id'] as String?;
      }

      // Upload media to Supabase Storage asynchronously
      _uploadMediaInBackground(
        jobId: jobId,
        wheelPhotos: Map.from(_wheelPhotos),
        vehiclePhotos: List.from(_vehiclePhotos),
        tyreQRImages: Map.from(_tyreQRImages),
        odometerPhoto: _odometerPhoto,
      );

      // Audio
      if (_audioPath != null) {
        final fileName = 'voice_note_${DateTime.now().millisecondsSinceEpoch}.webm';
        final mimeType = 'audio/webm';
        Uint8List audioBytes;
        if (kIsWeb) {
          final response = await http.get(Uri.parse(_audioPath!));
          audioBytes = response.bodyBytes;
        } else {
          final audioFile = File(_audioPath!);
          audioBytes = await audioFile.readAsBytes();
        }
        final vehicleNo = (_vehicleDetails?['Vehicle Number'] as String?) ?? 'unknown';
        await LocalMediaService().saveMediaBytes(
          bytes: audioBytes,
          vehicleNo: vehicleNo,
          
          mediaType: 'audio',
          mimeType: mimeType,
          fileName: fileName,
          jobId: jobId,
        );
      }

      // Update booking status if this was created from a direct booking
      if (widget.bookingId != null) {
        await supabase.from('bookings').update({
          'status': 'Job Card Created',
        }).eq('id', widget.bookingId!);
      }

      final String formattedNow = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      _showSuccessSnackBar(isDraft 
          ? 'Draft saved successfully on $formattedNow!' 
          : ((widget.draftJob != null && widget.draftJob?['status'] != AppConstants.statusDraft)
              ? 'Job card updated successfully!' 
              : 'Job card created successfully!${(_wheelPhotos.isNotEmpty || _audioPath != null) ? ' Media saved locally for this job.' : ''}'));

      if (mounted) {
        // ✅ FIX: Pass the integer user ID to refresh
        await Provider.of<ReportProvider>(context, listen: false)
            .refresh(user['id']);
        
        // Show WhatsApp share dialog if tyre details exist (only when creating full job card, not on draft)
        if (!isDraft && tyreDetails.isNotEmpty && widget.draftJob?['status'] != AppConstants.statusWorkInProgress) {
          final String displayJobId = jobCardId?.isNotEmpty == true ? jobCardId! : jobId.toString();
          await _showWhatsAppShareDialog(displayJobId, tyreDetails);
        }

        // If this was opened for editing/draft, pop back after saving
        if (widget.bookingId != null || widget.draftJob != null) {
          Navigator.of(context).pop(true);
          return;
        }
      }
      _resetScreen();
    } catch (error) {
      _showErrorSnackBar('Failed to save Job Card. Error: $error');
    } finally {
      if (mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadMediaInBackground({
    required int jobId,
    required Map<String, dynamic> wheelPhotos,
    required List<dynamic> vehiclePhotos,
    required Map<String, dynamic> tyreQRImages,
    required dynamic odometerPhoto,
  }) async {
    List<String> uploadedUrls = [];
    List<Future<String?>> uploadTasks = [];

    for (final entry in wheelPhotos.entries) {
      if (entry.value is String) continue;
      final position = entry.key;
      final photoXFile = entry.value as XFile;
      final fileName = 'job_${jobId}_wheel_${position.replaceAll(" ", "_")}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      uploadTasks.add(photoXFile.readAsBytes().then((bytes) => SupabaseService().uploadJobMedia(bytes, fileName)));
    }
    
    for (int i = 0; i < vehiclePhotos.length; i++) {
      if (vehiclePhotos[i] is String) continue;
      final photoXFile = vehiclePhotos[i] as XFile;
      uploadTasks.add(photoXFile.readAsBytes().then((bytes) => SupabaseService().uploadJobMedia(bytes, 'job_${jobId}_vehicle_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg')));
    }
    
    for (final entry in tyreQRImages.entries) {
      if (entry.value is String) continue;
      final position = entry.key;
      final imageBytes = entry.value as Uint8List;
      uploadTasks.add(SupabaseService().uploadJobMedia(imageBytes, 'job_${jobId}_tyreqr_${position.replaceAll(" ", "_")}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    }

    if (odometerPhoto != null && odometerPhoto is! String) {
      final photoXFile = odometerPhoto as XFile;
      uploadTasks.add(photoXFile.readAsBytes().then((bytes) => SupabaseService().uploadJobMedia(bytes, 'job_${jobId}_odometer_${DateTime.now().millisecondsSinceEpoch}.jpg')));
    }
    
    final results = await Future.wait(uploadTasks);
    uploadedUrls = results.where((url) => url != null).cast<String>().toList();

    // Update the reports table with the photo_urls (merging with existing draft photos if any)
    if (uploadedUrls.isNotEmpty) {
      List<String> finalUrls = List.from(uploadedUrls);
      final existingPhotos = widget.draftJob?['photo_urls'];
      if (existingPhotos != null) {
        List<String> prevUrls = [];
        if (existingPhotos is String) {
          try { prevUrls = List<String>.from(jsonDecode(existingPhotos)); } catch (_) {}
        } else if (existingPhotos is List) {
          prevUrls = List<String>.from(existingPhotos.map((e) => e.toString()));
        }
        for (final u in prevUrls) {
          if (!finalUrls.contains(u)) finalUrls.add(u);
        }
      }
      await supabase.from('reports').update({
        'photo_urls': finalUrls
      }).eq('id', jobId);
    }
  }

  Future<void> _showWhatsAppShareDialog(String jobIdStr, Map<String, Map<String, String>> tyreDetails) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Share Warranty Details'),
        content: const Text('Would you like to share the tyre warranty details via WhatsApp to the data entry team?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _shareToWhatsApp(jobIdStr, tyreDetails);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share to WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareToWhatsApp(String jobIdStr, Map<String, Map<String, String>> tyreDetails) async {
    final vehicleNo = _vehicleDetails?['Vehicle Number'] ?? _vehicleNumberController.text.trim();
    final clientName = _newClientNameController.text.trim();
    final clientPhone = _newClientPhoneController.text.trim();
    final vehicleBrand = _vehicleDetails?['vehicle_models']?['brand'] ?? 'N/A';
    final vehicleModel = _vehicleDetails?['vehicle_models']?['Model name'] ?? 'N/A';
    final odo = _newOdometerController.text.trim().isNotEmpty ? _newOdometerController.text.trim() : _odometerController.text.trim();

    try {
      final pdf = pw.Document();

      for (final entry in tyreDetails.entries) {
        final position = entry.key;
        final details = entry.value;
        final hasImage = details['has_image'] == 'true';
        final spec = details['spec'] ?? '';

        // Only add a PDF page if a QR image was actually captured for this wheel
        if (!hasImage || _tyreQRImages[position] == null) continue;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(
                    level: 0,
                    child: pw.Text('Tyre Warranty Details - $position', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('Job Card: $jobIdStr', style: const pw.TextStyle(fontSize: 16)),
                  if (vehicleNo.isNotEmpty && vehicleNo != 'Courier Package' && vehicleNo != 'N/A') ...[
                    pw.Text('Vehicle: $vehicleNo', style: const pw.TextStyle(fontSize: 16)),
                    if (vehicleBrand.isNotEmpty || vehicleModel.isNotEmpty)
                      pw.Text('Model: $vehicleBrand $vehicleModel', style: const pw.TextStyle(fontSize: 16)),
                    if (odo.isNotEmpty && odo != 'N/A')
                      pw.Text('Odometer Reading: $odo km', style: const pw.TextStyle(fontSize: 16)),
                  ],
                  pw.Text('Client: $clientName ($clientPhone)', style: const pw.TextStyle(fontSize: 16)),
                  if (_courierAddressController.text.trim().isNotEmpty)
                    pw.Text('Address: ${_courierAddressController.text.trim()}', style: const pw.TextStyle(fontSize: 16)),
                  pw.SizedBox(height: 20),
                  if (spec.isNotEmpty) pw.Text('Spec: $spec', style: const pw.TextStyle(fontSize: 16)),
                  pw.SizedBox(height: 10),
                  if (hasImage && _tyreQRImages[position] != null)
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Image(
                          pw.MemoryImage(_tyreQRImages[position]!),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      }

      final bytes = await pdf.save();
      
      // Save PDF to temp directory
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/job_${jobIdStr}_warranty_qrs.pdf');
      await file.writeAsBytes(bytes);

      // Share PDF
      final String message = 'Warranty details for Job Card $jobIdStr (Vehicle: $vehicleNo)';
      await Share.shareFiles(
        [file.path],
        text: message,
        subject: 'Warranty details for Job Card $jobIdStr',
      );
    } catch (e) {
      _showErrorSnackBar('Error generating or sharing PDF: $e');
    }
  }

  Future<String?> _showSearchableDropdown(String title, List<String> items) async {
    String searchQuery = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredItems = items
                .where((item) => item.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();
            final typed = searchQuery.trim();
            final canCreate = typed.isNotEmpty &&
                !items.any((item) => item.toLowerCase() == typed.toLowerCase());
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Type to filter or add new',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredItems.length + (canCreate ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (canCreate && index == filteredItems.length) {
                            return ListTile(
                              leading: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                              title: Text(
                                'Create new “$typed”',
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => Navigator.pop(context, typed),
                            );
                          }
                          return ListTile(
                            title: Text(filteredItems[index]),
                            onTap: () => Navigator.pop(context, filteredItems[index]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- UI & MEDIA HELPERS ---

  void _showServiceCatalogModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ServiceCatalogPicker(
        serviceCatalog: _serviceCatalog,
        onServiceSelected: (String serviceName, double? defaultPrice) {
          _complaintInputController.text = serviceName;
          _addComplaint();
        },
      ),
    );
  }

  void _addComplaint() {
    final complaintText = _complaintInputController.text.trim();

    // ✅ Validate complaint is not empty
    final error = Validators.validateRequired(complaintText);
    if (error != null) {
      _showErrorSnackBar(error);
      return;
    }

    // Lookup default price
    double price = 0;
    for (var service in _serviceCatalog) {
      if (service['name'].toString().toLowerCase() == complaintText.toLowerCase()) {
        if (service['default_price'] != null) {
          price = (service['default_price'] as num).toDouble();
        }
        break;
      }
    }

    setState(() {
      _complaints.add({
        'text': complaintText,
        'amount': price,
        'type': AppConstants.typeComplaint
      });
      _complaintInputController.clear();
    });
  }

  void _addTyreComplaint() {
    final brand = _tyreBrandController.text.trim();
    final model = _tyreModelController.text.trim();
    final size = _tyreSizeController.text.trim();
    final liSi = _tyreLiSiController.text.trim();

    if (brand.isEmpty && size.isEmpty) {
      _showErrorSnackBar('Please browse and select a Tyre from catalog.');
      return;
    }
    final modelStr = model.isNotEmpty ? ' $model' : '';
    final sizeStr = size.isNotEmpty ? ' $size' : '';
    final liSiStr = liSi.isNotEmpty ? ' $liSi' : '';
    final complaintText = 'Tyre - $brand$modelStr$sizeStr$liSiStr';

    double unitPrice = double.tryParse(_tyrePriceController.text) ?? 0.0;
    int count = int.tryParse(_tyreCountController.text) ?? 1;
    if (count < 1) count = 1;
    double totalPrice = double.tryParse(_tyreTotalController.text) ?? (unitPrice * count);

    setState(() {
      _complaints.add({
        'text': complaintText,
        'amount': totalPrice,
        'unit_price': unitPrice,
        'count': count,
        'type': AppConstants.typeComplaint
      });

      _tyreBrandController.clear();
      _tyreModelController.clear();
      _tyreSizeController.clear();
      _tyreLiSiController.clear();
      _tyrePriceController.clear();
      _tyreTotalController.clear();
      _tyreCountController.text = '1';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "$complaintText" ($count × ₹${unitPrice.toStringAsFixed(2)})'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  void _addAlloyComplaint() {
    final model = _alloyModelController.text.trim();
    final size = _alloySizeController.text.trim();
    final brand = _alloyBrandController.text.trim();

    if (model.isEmpty && brand.isEmpty) {
      _showErrorSnackBar('Please browse and select an Alloy Wheel.');
      return;
    }

    final displayName = model.isNotEmpty ? model : brand;
    final sizeStr = size.isNotEmpty && !displayName.contains(size) ? ' ($size)' : '';
    final complaintText = 'Alloy - $displayName$sizeStr';

    double unitPrice = double.tryParse(_alloyPriceController.text) ?? 0.0;
    int count = int.tryParse(_alloyCountController.text) ?? 4;
    if (count < 1) count = 1;
    double totalPrice = double.tryParse(_alloyTotalController.text) ?? (unitPrice * count);

    setState(() {
      _complaints.add({
        'text': complaintText,
        'amount': totalPrice,
        'unit_price': unitPrice,
        'count': count,
        'type': AppConstants.typeComplaint,
      });

      _alloyBrandController.clear();
      _alloyModelController.clear();
      _alloySizeController.clear();
      _alloyPriceController.clear();
      _alloyTotalController.clear();
      _alloyCountController.text = '4';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "$complaintText" ($count × ₹${unitPrice.toStringAsFixed(2)})'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  void _deleteComplaint(int index) {
    setState(() => _complaints.removeAt(index));
  }

  void _editComplaintAmount(int index) {
    final complaint = _complaints[index];
    final String text = (complaint['name'] ?? complaint['text'] ?? '').toString();
    final bool isTyre = text.toLowerCase().startsWith('tyre');
    final bool isAlloy = text.toLowerCase().startsWith('alloy') || complaint['is_alloy'] == true;

    final int initialQty = int.tryParse('${complaint['count'] ?? complaint['qty'] ?? 1}') ?? 1;
    final double initialTotal = ((complaint['amount'] ?? 0) as num).toDouble();
    final double initialDiscount = ((complaint['discount'] ?? 0) as num).toDouble();
    double initialUnitPrice = ((complaint['unit_price'] ?? 0) as num).toDouble();
    if (initialUnitPrice <= 0 && initialQty > 0) {
      initialUnitPrice = (initialTotal + initialDiscount) / initialQty;
    }

    final TextEditingController editQtyController = TextEditingController(
      text: initialQty.toString(),
    );
    final TextEditingController editUnitPriceController = TextEditingController(
      text: initialUnitPrice > 0 ? initialUnitPrice.toStringAsFixed(0) : '',
    );
    final TextEditingController editDiscountController = TextEditingController(
      text: initialDiscount > 0 ? initialDiscount.toStringAsFixed(0) : '',
    );
    final TextEditingController editAmountController = TextEditingController(
      text: initialTotal > 0 ? initialTotal.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String badgeLabel = 'Service';
          Color badgeColor = Colors.orange;
          if (isTyre) {
            badgeLabel = 'Tyre';
            badgeColor = Colors.blue;
          } else if (isAlloy) {
            badgeLabel = 'Alloy';
            badgeColor = const Color(0xFF0D9488);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: editQtyController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Count',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            final int newQty = int.tryParse(val) ?? 1;
                            final double unitP = double.tryParse(editUnitPriceController.text) ?? 0;
                            final double disc = double.tryParse(editDiscountController.text) ?? 0;
                            final double newTotal = (unitP * newQty) - disc;
                            final finalTotal = newTotal > 0 ? newTotal : 0.0;
                            setDialogState(() {
                              editAmountController.text = finalTotal > 0 ? finalTotal.toStringAsFixed(0) : '0';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: editUnitPriceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: InputDecoration(
                            labelText: isTyre ? 'Price / Tyre' : (isAlloy ? 'Price / Alloy' : 'Unit Price'),
                            prefixText: '₹',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            final double unitP = double.tryParse(val) ?? 0;
                            final int currentQty = int.tryParse(editQtyController.text) ?? 1;
                            final double disc = double.tryParse(editDiscountController.text) ?? 0;
                            final double newTotal = (unitP * currentQty) - disc;
                            final finalTotal = newTotal > 0 ? newTotal : 0.0;
                            setDialogState(() {
                              editAmountController.text = finalTotal > 0 ? finalTotal.toStringAsFixed(0) : '0';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: editDiscountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: const InputDecoration(
                            labelText: 'Discount (₹)',
                            prefixText: '₹',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            final double disc = double.tryParse(val) ?? 0;
                            final double unitP = double.tryParse(editUnitPriceController.text) ?? 0;
                            final int currentQty = int.tryParse(editQtyController.text) ?? 1;
                            final double newTotal = (unitP * currentQty) - disc;
                            final finalTotal = newTotal > 0 ? newTotal : 0.0;
                            setDialogState(() {
                              editAmountController.text = finalTotal > 0 ? finalTotal.toStringAsFixed(0) : '0';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: editAmountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: const InputDecoration(
                            labelText: 'Total (₹)',
                            prefixText: '₹',
                            isDense: true,
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFEFF6FF),
                          ),
                          onChanged: (val) {
                            final double newTotal = double.tryParse(val) ?? 0;
                            final int currentQty = int.tryParse(editQtyController.text) ?? 1;
                            final double disc = double.tryParse(editDiscountController.text) ?? 0;
                            final double computedUnitP = currentQty > 0 ? ((newTotal + disc) / currentQty) : newTotal;
                            setDialogState(() {
                              editUnitPriceController.text = computedUnitP > 0 ? computedUnitP.toStringAsFixed(0) : '0';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final double? parsedAmount = double.tryParse(editAmountController.text);
                  final double? parsedUnitPrice = double.tryParse(editUnitPriceController.text);
                  final double? parsedDiscount = double.tryParse(editDiscountController.text);
                  final int? parsedQty = int.tryParse(editQtyController.text);

                  setState(() {
                    if (parsedAmount != null) _complaints[index]['amount'] = parsedAmount;
                    if (parsedUnitPrice != null) _complaints[index]['unit_price'] = parsedUnitPrice;
                    if (parsedDiscount != null) _complaints[index]['discount'] = parsedDiscount;
                    if (parsedQty != null) {
                      _complaints[index]['count'] = parsedQty;
                      _complaints[index]['qty'] = parsedQty;
                    }
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    // We only use the custom in-app scanner for number plates now
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NumberPlateScannerScreen(),
      ),
    );

    if (result != null && result is Uint8List) {
      setState(() => _isLoading = true);
      try {
        final plateNumber = await OcrService.recognizeVehicleNumber(result);
        if (plateNumber != null) {
          _vehicleNumberController.text = plateNumber;
          await _searchVehicle();
        } else {
          _showErrorSnackBar(
              'Could not detect a valid number plate. Please try again.');
        }
      } catch (e) {
        _showErrorSnackBar('OCR failed: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startRapidCapture() async {
    final List<String> missingWheels = _requiredWheels.where((w) => !_wheelPhotos.containsKey(w)).toList();
    
    if (missingWheels.isEmpty) {
      _showErrorSnackBar('All required photos are already taken!');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiWheelCameraScreen(targets: missingWheels),
      ),
    );

    if (result != null && result is Map<String, XFile>) {
      setState(() {
        _wheelPhotos.addAll(result);
      });
    }
  }

  Widget _buildPhotoSlot(String label, dynamic photo, VoidCallback onTap, VoidCallback onRemove) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              InkWell(
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: photo == null
                    ? const Icon(Icons.add_a_photo, color: Colors.grey, size: 30)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: photo is String ? AppCachedImage(imageUrl: photo, fit: BoxFit.cover) : Image.file(File(photo.path), fit: BoxFit.cover),
                      ),
              ),
            ),
            if (photo != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _pickWheelPhoto(String position) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiWheelCameraScreen(targets: [position]),
      ),
    );

    if (result != null && result is Map<String, XFile> && result.containsKey(position)) {
      setState(() => _wheelPhotos[position] = result[position]!);
    }
  }

  void _removeWheelPhoto(String position) {
    setState(() => _wheelPhotos.remove(position));
  }

  Future<void> _pickVehiclePhoto() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ContinuousCameraScreen(),
      ),
    );

    if (result != null && result is List<String>) {
      setState(() {
        for (String path in result) {
          _vehiclePhotos.add(XFile(path));
        }
      });
    }
  }
  
  void _removeVehiclePhoto(int index) {
    setState(() => _vehiclePhotos.removeAt(index));
  }

  Future<void> _captureOdometerPhoto() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OdometerCameraScreen(),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        if (result['photo'] != null) {
          _odometerPhoto = result['photo'];
        }
        if (result['reading'] != null && result['reading'].toString().isNotEmpty) {
          _odometerController.text = result['reading'];
          _odometerError = Validators.validateOdometer(result['reading']);
        }
      });
    }
  }

  List<Widget> _buildDynamicTechnicianAssignments() {
    // Group technicians by role
    final Map<String, List<Map<String, dynamic>>> techsByRole = {};
    for (var tech in _allTechnicians) {
      final role = tech['role']?.toString() ?? 'Unassigned';
      techsByRole.putIfAbsent(role, () => []).add(tech);
    }

    List<Widget> widgets = [];
    techsByRole.forEach((role, techs) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role.toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...techs.map((tech) {
                final isSelected = _technicianAssignments.any((a) => a['tech_id'] == tech['id']);
                return CheckboxListTile(
                  title: Text(tech['username'] ?? 'Unknown', style: const TextStyle(fontSize: 14)),
                  value: isSelected,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (bool? checked) {
                    setState(() {
                      if (checked == true) {
                        _technicianAssignments.add({'role': role, 'tech_id': tech['id']});
                      } else {
                        _technicianAssignments.removeWhere((a) => a['tech_id'] == tech['id']);
                      }
                    });
                  },
                );
              }).toList(),
            ],
          ),
        ),
      );
    });

    if (widgets.isEmpty) {
      return [const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('No technicians available.'))];
    }
    return widgets;
  }

  Future<void> _scanTyreQR(String wheel) async {
    try {
        final ImageSource? source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (BuildContext context) {
            return SafeArea(
              child: Wrap(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.of(context).pop(ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                  ),
                ],
              ),
            );
          },
        );

        if (source == null) return;

        final picker = ImagePicker();
        final XFile? photo = await picker.pickImage(source: source);
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _tyreQRImages[wheel] = bytes;
          });
        }
    } catch (e) {
      _showErrorSnackBar('Failed to capture QR photo for $wheel: $e');
    }
  }

  Widget _buildTyreWarrantyRow(String wheel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            wheel,
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_tyreQRImages[wheel] != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusSm),
                      child: _tyreQRImages[wheel] is String
                          ? AppCachedImage(
                              imageUrl: _tyreQRImages[wheel],
                              height: 80,
                              width: 80,
                              fit: BoxFit.cover,
                            )
                          : Image.memory(
                              _tyreQRImages[wheel] as Uint8List,
                              height: 80,
                              width: 80,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _tyreQRImages.remove(wheel);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _scanTyreQR(wheel),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Capture QR'),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() {
          _isRecording = false;
          _audioPath = path;
        });
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isRecording = true;
          _audioPath = null;
        });

        if (kIsWeb) {
          await _audioRecorder
              .start(const RecordConfig(encoder: AudioEncoder.opus), path: '');
        } else {
          final tempDir = await getTemporaryDirectory();
          final path =
              '${tempDir.path}/audiorecord_${DateTime.now().millisecondsSinceEpoch}.webm';
          await _audioRecorder.start(
              const RecordConfig(encoder: AudioEncoder.opus),
              path: path);
        }
      } else {
        _showErrorSnackBar('Microphone permission not granted.');
      }
    }
  }

  void _undoLastMark() {
    if (_damageMarks.isNotEmpty) setState(() => _damageMarks.removeLast());
  }

  void _clearDamageMarks() {
    setState(() => _damageMarks.clear());
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    String displayMessage = message;
    final lower = message.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('connection abort') ||
        lower.contains('failed host lookup') ||
        lower.contains('network_error') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed to connect')) {
      displayMessage = '📶 No internet connection. Please check your network and try again.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayMessage,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusLg)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    // Commented out to reduce UI noise
    // if (!mounted) return;
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(message),
    //     backgroundColor: Colors.green,
    //     behavior: SnackBarBehavior.floating,
    //     shape: RoundedRectangleBorder(
    //         borderRadius: BorderRadius.circular(AppTheme.borderRadiusLg)),
    //     margin: const EdgeInsets.all(16),
    //   ),
    // );
  }

  // --- WIDGET BUILDER METHODS ---

  @override
  Widget build(BuildContext context) {
    return _buildMainScaffold();
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          children: [
            Text(
              _isCourierMode
                  ? (widget.draftJob != null ? 'Edit Courier Job Card' : 'Courier Job Card')
                  : (widget.draftJob?['status'] == AppConstants.statusEditRequested ? 'Edit Services & Tyres' : 'Job Card'),
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            if (CompanyService().companyName != null && CompanyService().companyName!.isNotEmpty)
              Text(
                CompanyService().companyName!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          CompanySwitcherBadge(onCompanyChanged: () => setState(() {})),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.primaryColor),
            tooltip: 'Options',
            onSelected: (value) {
              if (value == 'drafts') {
                _openFullPageRegistrationDrafts();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'drafts',
                child: Row(
                  children: [
                    Icon(Icons.drafts_outlined, color: Colors.purple, size: 20),
                    SizedBox(width: 10),
                    Text('Saved Registration Drafts', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          controller: _mainScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.draftJob == null) ...[
                _buildModeToggle(),
                const SizedBox(height: 16),
              ],
              
              if (!_isCourierMode) ...[
                // ✅ Hide search bar and vehicle creation form when editing a vehicle draft
                // (vehicle already exists — skip straight to complaint section)
                if (!_isVehicleJobCardDraft) _buildSearchCard(),

                if (_isLoading &&
                    _vehicleDetails == null &&
                    !_showCreateVehicleForm)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),

                if (_vehicleDetails != null)
                  _buildVehicleDetailsCard(_vehicleDetails!),
                // ✅ Only show vehicle creation form when NOT editing a vehicle draft
                if (_showCreateVehicleForm && !_isVehicleJobCardDraft)
                  _buildCreateVehicleForm(),
                if (_vehicleDetails != null || _isVehicleJobCardDraft)
                  _buildNewComplaintCard(),
              ] else ...[
                _buildCourierForm(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Google Drive status UI removed

  Widget _buildSearchCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search mode toggle (Vehicle Number vs Mobile Number)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_searchByMobile) {
                        setState(() {
                          _searchByMobile = false;
                          _searchError = null;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_searchByMobile ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: !_searchByMobile
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car_outlined,
                            size: 16,
                            color: !_searchByMobile ? AppTheme.primaryColor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Vehicle No.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: !_searchByMobile ? FontWeight.w700 : FontWeight.w500,
                              color: !_searchByMobile ? AppTheme.primaryColor : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (!_searchByMobile) {
                        setState(() {
                          _searchByMobile = true;
                          _searchError = null;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _searchByMobile ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _searchByMobile
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.phone_android_outlined,
                            size: 16,
                            color: _searchByMobile ? AppTheme.primaryColor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Mobile No.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _searchByMobile ? FontWeight.w700 : FontWeight.w500,
                              color: _searchByMobile ? AppTheme.primaryColor : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (!_searchByMobile) ...[
            const FormLabel(text: 'Vehicle No:'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _vehicleNumberController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter vehicle number or scan',
                      errorText: _vehicleNumberError, // ✅ Show validation error
                      suffixIcon: _buildCameraIcon(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _searchVehicle(),
                    onChanged: (value) {
                      // ✅ Validate on change
                      setState(() {
                        _vehicleNumberController.value = TextEditingValue(
                          text: value.toUpperCase(),
                          selection: _vehicleNumberController.selection,
                        );
                        _vehicleNumberError =
                            Validators.validateVehicleNumber(value);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buildMinimalSearchButton(onTap: _searchVehicle, tooltip: 'Search Vehicle'),
              ],
            ),
          ] else ...[
            const FormLabel(text: 'Customer Mobile No:'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mobileSearchController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Enter 10-digit mobile number',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      errorText: _mobileSearchError,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _searchByMobileNumber(),
                    onChanged: (value) {
                      if (_mobileSearchError != null) {
                        setState(() => _mobileSearchError = null);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buildMinimalSearchButton(onTap: _searchByMobileNumber, tooltip: 'Search Mobile'),
              ],
            ),
          ],
          if (_searchError != null && !_showCreateVehicleForm)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_searchError!,
                  style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  // ✅ NEW: Camera icon inside search field (conditionally shown based on feature flag)
  Widget _buildCameraIcon() {
    return Consumer<AdminSettingsProvider>(
      builder: (context, settingsProvider, _) {
        // Hide camera icon if number plate scanner is disabled
        if (!settingsProvider.featureScanner) {
          return const SizedBox.shrink();
        }
        
        return GestureDetector(
          onTap: () => _pickImage(ImageSource.camera),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.camera_alt,
              color: Colors.grey[600],
              size: 20,
            ),
          ),
        );
      },
    );
  }

  // ✅ NEW: Minimal search button
  Widget _buildMinimalSearchButton({VoidCallback? onTap, String tooltip = 'Search Vehicle'}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _isLoading ? null : (onTap ?? _searchVehicle),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.blue[600],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(
                    Icons.search,
                    color: Colors.white,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildVehicleDetailsCard(Map<String, dynamic> details) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 24),
              SizedBox(width: 8),
              Text(
                'Vehicle Found',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green),
              ),
            ],
          ),
          const Divider(height: 24),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildDetailItem(
                      'Vehicle Number', details['Vehicle Number'] ?? 'N/A')),
              Expanded(
                  child: _buildDetailItem(
                      'Vehicle Name', details['vehicle_name'] ?? 'N/A')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildDetailItem(
                      'Brand', details['vehicle_models']?['brand'] ?? 'N/A')),
              Expanded(
                  child: _buildDetailItem(
                      'Model', details['vehicle_models']?['Model name'] ?? 'N/A')),
            ],
          ),
          const Divider(height: 32),

          if (widget.draftJob?['status'] != AppConstants.statusEditRequested) ...[
            // ✅ Display Caution if details differ
          if (_clientNameDiffers || _clientPhoneDiffers)
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingSm),
              margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withAlpha((255 * 0.1).round()),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusSm),
                border: Border.all(
                    color:
                        AppTheme.warningColor.withAlpha((255 * 0.5).round())),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warningColor, size: 18),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Text(
                      'Client details differ from the vehicle\'s original record. Using latest info.',
                      style: TextStyle(
                          color: AppTheme.warningColor
                              .withAlpha((255 * 0.9).round()),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          // --- END CAUTION ---

          const FormLabel(text: 'Client Name'),
          TextField(
            controller:
                _newClientNameController, // Already populated with latest
            decoration: const InputDecoration(hintText: 'Enter client name'),
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Client Phone'),
          TextField(
            controller: _newClientPhoneController,
            decoration: InputDecoration(
              hintText:
                  'Enter 10-digit phone number', // Already populated with latest
              counterText: "",
              errorText: _phoneError, // Show validation error
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: (value) {
              // Validate on change
              setState(() {
                _phoneError = Validators.validatePhoneNumber(value);
              });
            },
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Client Mobile Number (Optional)'),
          TextField(
            controller: _newClientMobileController,
            decoration: const InputDecoration(
              hintText: 'Enter 10-digit mobile number',
              counterText: "",
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'GST Number'),
          TextField(
            controller: _ownerGstController,
            decoration: const InputDecoration(
              hintText: 'e.g., 27AABCT1234H1Z0',
            ),
          ),
          const SizedBox(height: 16),

          const FormLabel(text: 'Odometer Reading', isRequired: true),
          TextField(
            controller: _odometerController, // Already populated with latest
            decoration: InputDecoration(
              hintText:
                  'Enter current kilometers', // ... (rest of odometer field, including potential warning)
              errorText: _odometerError, // Show validation error
              suffixIcon: IconButton(
                icon: Icon(
                  _odometerPhoto != null ? Icons.check_circle : Icons.document_scanner,
                  color: _odometerPhoto != null ? Colors.green : AppTheme.primaryColor,
                ),
                onPressed: _captureOdometerPhoto,
                tooltip: 'Scan Odometer',
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              // Validate on change
              setState(() {
                if (value.trim().isEmpty) {
                  _odometerError = 'Odometer reading is required';
                } else {
                  _odometerError = Validators.validateOdometer(value.trim());
                }
              });
            },
          ),
          // Non-blocking warning if odometer entered is lower than last known
          if (_lastKnownOdometer != null &&
              int.tryParse(_odometerController.text) != null &&
              (int.tryParse(_odometerController.text)!) < _lastKnownOdometer!)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Entered reading is lower than last recorded ($_lastKnownOdometer km). Please verify.',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            
          if (_odometerPhoto != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _odometerPhoto is String ? AppCachedImage(
                        imageUrl: _odometerPhoto,
                        fit: BoxFit.cover,
                      ) : Image.file(
                        File(_odometerPhoto.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _odometerPhoto = null;
                      });
                    },
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    label: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),
          // --- Buyback Option ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _isBuyback ? AppTheme.primaryColor.withAlpha((255 * 0.1).round()) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusSm),
              border: Border.all(
                color: _isBuyback ? AppTheme.primaryColor : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.swap_horizontal_circle_outlined,
                      color: _isBuyback ? AppTheme.primaryColor : AppTheme.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Buyback',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _isBuyback ? AppTheme.primaryColor : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Include buyback in order narration',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _isBuyback,
                  activeTrackColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    setState(() {
                      _isBuyback = val;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
        ],
      ),
    );
  }

  Widget _buildCreateVehicleForm() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isFoundInTally ? Icons.check_circle : Icons.add_circle, color: _isFoundInTally ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Text(
                _isFoundInTally ? 'Saved in Tally' : 'Register New Vehicle',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _isFoundInTally ? Colors.green : Colors.orange),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              _isFoundInTally
                  ? "Vehicle details found in Tally and auto-filled below. Review and save."
                  : "Vehicle not found. Please add the details below.",
              style: TextStyle(
                color: _isFoundInTally ? Colors.green.shade700 : AppTheme.textSecondary,
                fontWeight: _isFoundInTally ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const Divider(height: 24),
          const FormLabel(text: 'Vehicle Number', isRequired: true),
          TextField(
            controller: _vehicleNumberController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. MH12AB1234',
              errorText: _vehicleNumberError,
            ),
            onChanged: (value) {
              setState(() {
                _vehicleNumberController.value = TextEditingValue(
                  text: value.toUpperCase(),
                  selection: _vehicleNumberController.selection,
                );
                _vehicleNumberError = Validators.validateVehicleNumber(value);
              });
            },
          ),
          const SizedBox(height: 16),
          Consumer<AdminSettingsProvider>(
            builder: (context, adminSettings, child) {
              if (!adminSettings.showFullVehicleForm) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                ],
              );
            },
          ),
          BrandModelSearchDropdown(
            initialBrand: _selectedBrand,
            initialModelId: _selectedModelId,
            initialModelName: _selectedModelName,
            onSelectionChanged: (brand, modelId, modelName) {
              setState(() {
                _selectedBrand = brand;
                _selectedModelId = modelId;
                _selectedModelName = modelName;
              });
            },
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Odometer Reading (km)', isRequired: true),
          TextField(
            controller: _newOdometerController,
            decoration: InputDecoration(
              hintText: 'e.g., 54000',
              errorText: _odometerError, // ✅ Show validation error
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              // ✅ Validate on change
              setState(() {
                if (value.trim().isEmpty) {
                  _odometerError = 'Odometer reading is required';
                } else {
                  _odometerError = Validators.validateOdometer(value.trim());
                }
              });
            },
          ),
          const Divider(height: 24),
          const FormLabel(text: 'Client Name', isRequired: true),
          TextField(
            controller: _newClientNameController,
            decoration: const InputDecoration(
              hintText: 'Enter client name',
            ),
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Client Phone', isRequired: true),
          TextField(
            controller: _newClientPhoneController,
            decoration: InputDecoration(
              hintText: 'e.g., 9876543210',
              counterText: "",
              errorText: _phoneError, // ✅ Show validation error
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: (value) {
              // ✅ Validate on change
              setState(() {
                _phoneError = Validators.validatePhoneNumber(value);
              });
            },
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Client Mobile Number (Optional)'),
          TextField(
            controller: _newClientMobileController,
            decoration: const InputDecoration(
              hintText: 'e.g., 9876543210',
              counterText: "",
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
          ),
          const SizedBox(height: 24),
          const FormLabel(text: 'GST Number'),
          TextField(
            controller: _ownerGstController,
            decoration: const InputDecoration(hintText: 'e.g., 27AABCT1234H1Z0'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _saveVehicleRegistrationDraft,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.purple),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save as Draft', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createVehicle,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Vehicle', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewComplaintCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.draftJob?['status'] == AppConstants.statusEditRequested ? 'Edit Services & Tyres' : 'Register New Complaint(s)',
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const Divider(height: 24),

          // ✅ Use EmptyDisplay widget
          if (_complaints.isEmpty)
            const EmptyDisplay(
              message: 'No complaints added yet.',
              icon: Icons.assignment_outlined,
              subtitle: 'Add complaints to continue',
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _complaints.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_complaints[index]['text']),
                                  if (_complaints[index]['discount'] != null && ((_complaints[index]['discount'] as num) > 0))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Disc: -₹${_complaints[index]['discount']}',
                                        style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_complaints[index]['count'] != null)
                              InkWell(
                                onTap: () => _editComplaintAmount(index),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Qty: ${_complaints[index]['count']}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            InkWell(
                              onTap: () => _editComplaintAmount(index),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _complaints[index]['amount'] != null && _complaints[index]['amount'] > 0
                                          ? '₹${_complaints[index]['amount']}'
                                          : 'Add ₹',
                                      style: const TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit, size: 12, color: AppTheme.primaryColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteComplaint(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _complaintInputController,
                  focusNode: _complaintFocusNode,
                  readOnly: true,
                  onTap: _showServiceCatalogModal,
                  decoration: const InputDecoration(
                    hintText: 'Select service from catalog...',
                    hintStyle: TextStyle(fontSize: 13),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    suffixIcon: Icon(Icons.list_alt, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_complaintInputController.text.trim().isEmpty) {
                    _showServiceCatalogModal();
                  } else {
                    _addComplaint();
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16),
                ),
                child: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: FormLabel(text: 'Tyre Specification (Applies to all)'),
              ),
              if (_tyreBrandController.text.isNotEmpty || _tyreSizeController.text.isNotEmpty) ...[
                InkWell(
                  onTap: () {
                    setState(() {
                      _tyreBrandController.clear();
                      _tyreModelController.clear();
                      _tyreSizeController.clear();
                      _tyreLiSiController.clear();
                      _tyrePriceController.clear();
                      _tyreTotalController.clear();
                      _tyreCountController.text = '1';
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text('Clear', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Browse & Selected Tyre Display Card (Database Selection Only)
          InkWell(
            onTap: () => _openTyreCatalogPicker(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_tyreModelController.text.isNotEmpty || _tyreBrandController.text.isNotEmpty)
                      ? AppTheme.primaryColor
                      : const Color(0xFFCBD5E1),
                  width: (_tyreModelController.text.isNotEmpty || _tyreBrandController.text.isNotEmpty) ? 1.5 : 1,
                ),
              ),
              child: (_tyreModelController.text.isNotEmpty || _tyreBrandController.text.isNotEmpty)
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _tyreSizeController.text.isNotEmpty
                                ? '${_tyreSizeController.text}${_tyreLiSiController.text.isNotEmpty ? ' ${_tyreLiSiController.text}' : ''}'
                                : 'Tyre',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tyreModelController.text.isNotEmpty
                                    ? _tyreModelController.text
                                    : _tyreBrandController.text,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_tyreBrandController.text.isNotEmpty)
                                Text(
                                  _tyreBrandController.text,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _openTyreCatalogPicker(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                            foregroundColor: AppTheme.primaryColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() {
                              _tyreBrandController.clear();
                              _tyreModelController.clear();
                              _tyreSizeController.clear();
                              _tyreLiSiController.clear();
                              _tyrePriceController.clear();
                              _tyreTotalController.clear();
                              _tyreCountController.text = '1';
                            });
                          },
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(Icons.search, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Browse & Select Tyre from DB...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _openTyreCatalogPicker(),
                          icon: const Icon(Icons.list_alt, size: 14),
                          label: const Text('Browse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tyreCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tyre Count',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => _syncTyreComplaint(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tyrePriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price/Tyre',
                    prefixText: '₹',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => _syncTyreComplaint(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tyreTotalController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Total',
                    prefixText: '₹',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.black12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.draftJob?['status'] != AppConstants.statusCompleted) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addTyreComplaint,
                icon: const Icon(Icons.add_shopping_cart, size: 20),
                label: const Text('Add Tyre', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Toggle Alloy Section Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showAlloySection = !_showAlloySection;
                  });
                },
                icon: Icon(
                  _showAlloySection ? Icons.remove_circle_outline : Icons.add_circle_outline,
                  size: 18,
                  color: const Color(0xFF0D9488),
                ),
                label: Text(
                  _showAlloySection ? 'Hide Alloy Section' : '+ Add Alloys',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D9488),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                  backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.05),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (_showAlloySection) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF99F6E4), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.album_outlined, color: Color(0xFF0D9488), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Alloy Wheel Specification',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _showAlloySection = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Browse & Selected Alloy Display Card
                    InkWell(
                      onTap: _openAlloyCatalogPicker,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _alloyModelController.text.isNotEmpty
                                ? const Color(0xFF0D9488)
                                : const Color(0xFFCBD5E1),
                            width: _alloyModelController.text.isNotEmpty ? 1.5 : 1,
                          ),
                        ),
                        child: _alloyModelController.text.isNotEmpty
                            ? Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _alloySizeController.text.isNotEmpty
                                          ? _alloySizeController.text
                                          : 'Alloy',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _alloyModelController.text,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (_alloyBrandController.text.isNotEmpty)
                                          Text(
                                            _alloyBrandController.text,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: _openAlloyCatalogPicker,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                      foregroundColor: const Color(0xFF0D9488),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      setState(() {
                                        _alloyBrandController.clear();
                                        _alloyModelController.clear();
                                        _alloySizeController.clear();
                                        _alloyPriceController.clear();
                                        _alloyTotalController.clear();
                                        _alloyCountController.text = '4';
                                      });
                                    },
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  const Icon(Icons.search, color: Color(0xFF0D9488), size: 20),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Browse & Select Alloy Wheel...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _openAlloyCatalogPicker,
                                    icon: const Icon(Icons.list_alt, size: 14),
                                    label: const Text('Browse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Count, Price/Alloy, Total Row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _alloyCountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Count',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (val) => _syncAlloyComplaint(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _alloyPriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Price/Alloy',
                              prefixText: '₹',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (val) => _syncAlloyComplaint(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _alloyTotalController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Total',
                              prefixText: '₹',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Color(0xFFCCFBF1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addAlloyComplaint,
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('Add Alloy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (widget.draftJob?['status'] != AppConstants.statusEditRequested) ...[
            const SizedBox(height: 24),
          const FormLabel(text: 'Tyre QR Photos'),
          const SizedBox(height: 8),
          // Individual tyre rows
          ..._requiredWheels.map((wheel) => _buildTyreWarrantyRow(wheel)).toList(),
          const Divider(height: 32),
          // ✅ Conditionally show damage marking section based on feature flag
          Consumer<AdminSettingsProvider>(
            builder: (context, settingsProvider, _) {
              // Hide Mark Damages on Vehicle for now
              return const SizedBox.shrink();
              /*
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: FormLabel(text: 'Mark Damages on Vehicle'),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AspectRatio(
                      aspectRatio: 0.8466666666666667,
                      child: GestureDetector(
                        onTapDown: (details) {
                          final imageBox = _imageKey.currentContext?.findRenderObject()
                              as RenderBox?;
                          if (imageBox == null || !imageBox.hasSize) return;

                          final localPos =
                              imageBox.globalToLocal(details.globalPosition);

                          if (localPos.dx >= 0 &&
                              localPos.dx <= imageBox.size.width &&
                              localPos.dy >= 0 &&
                              localPos.dy <= imageBox.size.height) {
                            final relX = localPos.dx / imageBox.size.width;
                            final relY = localPos.dy / imageBox.size.height;
                            setState(() => _damageMarks.add(Offset(relX, relY)));
                          }
                        },
                        child: CustomPaint(
                          foregroundPainter: DamagePainter(marks: _damageMarks),
                          child: Image.asset(
                            'assets/images/car_outline.png',
                            key: _imageKey,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: double.infinity,
                                height: 250,
                                color: Colors.grey.shade200,
                                child: const Center(child: Text('Car image missing')),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Click on the car image to mark scratches/damages.',
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Undo Last'),
                          onPressed: _undoLastMark,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            backgroundColor: Colors.blue.shade50,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_sweep, size: 18),
                          label: const Text('Clear All'),
                          onPressed: _clearDamageMarks,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            backgroundColor: Colors.red.shade50,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                ],
              );
              */
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FormLabel(text: kIsWeb ? 'Wheel Photos (Optional on Web)' : 'Wheel Photos (5 required)'),
              ),
              if (!kIsWeb && _wheelPhotos.length < 5)
                ElevatedButton.icon(
                  onPressed: _startRapidCapture,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Start Capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: _requiredWheels.map<Widget>((wheel) {
              final file = _wheelPhotos[wheel];
              return _buildPhotoSlot(wheel, file, () => _pickWheelPhoto(wheel), () => _removeWheelPhoto(wheel));
            }).toList(),
          ),
          const SizedBox(height: 16),
          const FormLabel(text: 'Overall Vehicle Photo (Optional) & Voice Note'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 120, // Match the typical height of an aspect ratio 1 box
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _vehiclePhotos.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _vehiclePhotos.length) {
                        return Container(
                          width: 120,
                          margin: const EdgeInsets.only(right: 8),
                          child: _buildPhotoSlot('Add Photo', null, _pickVehiclePhoto, () {}),
                        );
                      }
                      return Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 8),
                        child: _buildPhotoSlot('Vehicle ${index + 1}', _vehiclePhotos[index], () {}, () => _removeVehiclePhoto(index)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic, size: 24),
                  label: Text(_isRecording ? 'Stop Recording' : 'Record Note'),
                  style: TextButton.styleFrom(
                    foregroundColor: _isRecording ? Colors.white : AppTheme.primaryColor,
                    backgroundColor: _isRecording ? Colors.red : Colors.blue.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          if (_audioPath != null && !_isRecording)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                children: [
                  const Text('Voice note recorded:'),
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.green),
                    onPressed: () {
                      final source = kIsWeb
                          ? UrlSource(_audioPath!)
                          : DeviceFileSource(_audioPath!);
                      _audioPlayer.play(source);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() => _audioPath = null),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          
          // Technician Assignments
          const FormLabel(text: 'Assign Technicians (Optional)'),
          const SizedBox(height: 8),
          ..._buildDynamicTechnicianAssignments(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _technicianAssignments.add({'role': null, 'tech_id': null});
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Technician'),
            ),
          ),
          const SizedBox(height: 24),



          ],
          Row(
            children: [
              if (widget.draftJob?['status'] != AppConstants.statusWorkInProgress && widget.draftJob?['status'] != AppConstants.statusEditRequested) ...[
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => _saveJobCard(isDraft: true),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Save as Draft',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _saveJobCard(isDraft: false),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      (widget.draftJob != null && widget.draftJob?['status'] != AppConstants.statusDraft) ? 'Save Updates' : 'Create Job Card',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isCourierMode = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: !_isCourierMode ? AppTheme.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '🚗 Vehicle Service',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: !_isCourierMode ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isCourierMode = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _isCourierMode ? AppTheme.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '📦 Send Courier',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _isCourierMode ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourierForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormLabel(text: 'Customer Details'),
              const SizedBox(height: 12),
              TextField(
                controller: _courierNameController,
                decoration: const InputDecoration(labelText: 'Customer Name', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _courierPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _courierAddressController,
                decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.home)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _courierGstController,
                decoration: const InputDecoration(labelText: 'GST Number (Optional)', prefixIcon: Icon(Icons.receipt)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormLabel(text: 'Package Products'),
              const SizedBox(height: 12),
              
              if (_courierProductsList.isEmpty)
                const EmptyDisplay(
                  message: 'No products added yet.',
                  icon: Icons.inventory_2_outlined,
                  subtitle: 'Add products to continue',
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _courierProductsList.length,
                  itemBuilder: (context, index) {
                    final product = _courierProductsList[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (product['category'] == 'Alloy' || (product['name'] ?? '').toString().startsWith('Alloy'))
                                                ? const Color(0xFF0D9488).withValues(alpha: 0.15)
                                                : AppTheme.primaryColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            (product['category'] == 'Alloy' || (product['name'] ?? '').toString().startsWith('Alloy'))
                                                ? 'Alloy'
                                                : 'Tyre',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: (product['category'] == 'Alloy' || (product['name'] ?? '').toString().startsWith('Alloy'))
                                                  ? const Color(0xFF0D9488)
                                                  : AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text('${product['brand'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${product['model'] ?? ''}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                    Text('${product['size'] ?? ''}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                    const SizedBox(height: 6),
                                    Text('Qty: ${product['qty']}  |  Unit: ₹${product['price']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final num price = (product['price'] is num)
                                      ? product['price'] as num
                                      : (double.tryParse(product['price']?.toString() ?? '0') ?? 0.0);
                                  final int qty = (product['qty'] is int)
                                      ? product['qty'] as int
                                      : (int.tryParse(product['qty']?.toString() ?? '1') ?? 1);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Total: ₹${(price * qty).toStringAsFixed(2)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            onPressed: () => _editCourierProduct(index),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                                            onPressed: () => _deleteCourierProduct(index),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                                  final qrImages = product['qr_images'] as List<dynamic>? ?? [];
                                  final int qty = (product['qty'] is int)
                                      ? product['qty'] as int
                                      : (int.tryParse(product['qty']?.toString() ?? '1') ?? 1);
                                  
                                  if (qrImages.isEmpty) {
                                    return ElevatedButton.icon(
                                      onPressed: () => _scanCourierProductQR(index),
                                      icon: const Icon(Icons.qr_code_scanner, size: 16),
                                      label: const Text('Scan QR / Barcode'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    );
                                  } else {
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: SizedBox(
                                            height: 40,
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: qrImages.length,
                                              itemBuilder: (context, i) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(right: 8),
                                                  child: GestureDetector(
                                                    onTap: () => _viewCourierQR(index, i),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: qrImages[i] is String ? AppCachedImage(imageUrl: qrImages[i], height: 40, width: 40, fit: BoxFit.cover) : Image.memory(qrImages[i] as Uint8List, height: 40, width: 40, fit: BoxFit.cover),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (qrImages.length < qty)
                                          ElevatedButton.icon(
                                            onPressed: () => _scanCourierProductQR(index),
                                            icon: const Icon(Icons.qr_code_scanner, size: 14),
                                            label: Text('Scan Remaining (${qty - qrImages.length})'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              textStyle: const TextStyle(fontSize: 12),
                                            ),
                                          )
                                        else if (qrImages.length > qty)
                                          const Row(
                                            children: [
                                              Icon(Icons.warning, color: Colors.orange, size: 16),
                                              SizedBox(width: 4),
                                              Text('Excess QRs (Delete)', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                        else
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                                              SizedBox(width: 4),
                                              Text('All QRs Scanned', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                      ],
                                    );
                                  }
                                },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
              const SizedBox(height: 16),
              // Category Toggle: Tyres vs Alloys
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_courierCategory != 'Tyre') {
                          setState(() {
                            _courierCategory = 'Tyre';
                            _courierProductBrand = null;
                            _courierProductModel = null;
                            _courierProductSize = null;
                            _courierProductPriceController.clear();
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _courierCategory == 'Tyre' ? AppTheme.primaryColor : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _courierCategory == 'Tyre' ? AppTheme.primaryColor : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.tire_repair, size: 16, color: _courierCategory == 'Tyre' ? Colors.white : Colors.grey.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Tyres',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _courierCategory == 'Tyre' ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_courierCategory != 'Alloy') {
                          setState(() {
                            _courierCategory = 'Alloy';
                            _courierProductBrand = null;
                            _courierProductModel = null;
                            _courierProductSize = null;
                            _courierProductPriceController.clear();
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _courierCategory == 'Alloy' ? const Color(0xFF0D9488) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _courierCategory == 'Alloy' ? const Color(0xFF0D9488) : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.album_outlined, size: 16, color: _courierCategory == 'Alloy' ? Colors.white : Colors.grey.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Alloys',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _courierCategory == 'Alloy' ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select ${_courierCategory == 'Alloy' ? 'Alloy Wheel' : 'Tyre'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_courierCategory == 'Alloy') {
                        _openAlloyCatalogPicker(forCourier: true);
                      } else {
                        _openTyreCatalogPicker(forCourier: true);
                      }
                    },
                    icon: const Icon(Icons.search, size: 14),
                    label: Text(
                      'Browse ${_courierCategory == 'Alloy' ? 'Alloys' : 'Tyres'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_courierCategory == 'Alloy' ? const Color(0xFF0D9488) : AppTheme.primaryColor).withValues(alpha: 0.12),
                      foregroundColor: _courierCategory == 'Alloy' ? const Color(0xFF0D9488) : AppTheme.primaryColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(color: _courierCategory == 'Alloy' ? const Color(0xFF0D9488) : AppTheme.primaryColor, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        List<String> brands = [];
                        if (_courierCategory == 'Alloy') {
                          if (_alloyCatalog.isEmpty) await _fetchAlloyCatalog();
                          brands = _alloyCatalog
                              .map((t) => AlloyCatalogHelper.extractBrand(t))
                              .where((b) => b.isNotEmpty && b != 'Alloy Wheels')
                              .toSet().toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        } else {
                          if (_tyreCatalog.isEmpty) await _fetchTyreCatalog();
                          brands = _tyreCatalog
                              .map((t) => TyreCatalogHelper.extractBrand(t))
                              .where((b) => b.isNotEmpty && b != 'Other')
                              .toSet().toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        }
                        final selected = await _showSearchableDropdown('Select Brand', brands);
                        if (selected != null) {
                          setState(() {
                            _courierProductBrand = selected;
                            _courierProductModel = null;
                            _courierProductSize = null;
                            _courierProductPriceController.clear();
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Brand', isDense: true, border: OutlineInputBorder()),
                        child: Text(_courierProductBrand ?? 'Select', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _courierProductBrand == null ? null : () async {
                        final brand = _courierProductBrand!.toLowerCase();
                        List<String> models = [];
                        if (_courierCategory == 'Alloy') {
                          models = _alloyCatalog
                              .where((t) => AlloyCatalogHelper.extractBrand(t).toLowerCase() == brand)
                              .map((t) => AlloyCatalogHelper.extractModel(t))
                              .where((m) => m.isNotEmpty)
                              .toSet().toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        } else {
                          models = _tyreCatalog
                              .where((t) => TyreCatalogHelper.extractBrand(t).toLowerCase() == brand)
                              .map((t) => TyreCatalogHelper.extractModel(t))
                              .where((m) => m.isNotEmpty)
                              .toSet().toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        }
                        final selected = await _showSearchableDropdown('Select Model', models);
                        if (selected != null) {
                          setState(() {
                            _courierProductModel = selected;
                            _courierProductSize = null;
                            _courierProductPriceController.clear();
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Model', isDense: true, border: OutlineInputBorder()),
                        child: Text(_courierProductModel ?? 'Select', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _courierProductModel == null ? null : () async {
                        final brand = (_courierProductBrand ?? '').toLowerCase();
                        final model = (_courierProductModel ?? '').toLowerCase();
                        List<String> sizes = [];
                        if (_courierCategory == 'Alloy') {
                          sizes = _alloyCatalog
                              .where((t) =>
                                  AlloyCatalogHelper.extractBrand(t).toLowerCase() == brand &&
                                  AlloyCatalogHelper.extractModel(t).toLowerCase() == model)
                              .map((t) => AlloyCatalogHelper.extractSize(t))
                              .where((s) => s.isNotEmpty)
                              .toSet().toList()
                            ..sort((a, b) {
                              final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
                              final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
                              return numA.compareTo(numB);
                            });
                        } else {
                          sizes = _tyreCatalog
                              .where((t) =>
                                  TyreCatalogHelper.extractBrand(t).toLowerCase() == brand &&
                                  TyreCatalogHelper.extractModel(t).toLowerCase() == model)
                              .map((t) => TyreCatalogHelper.extractSize(t))
                              .where((s) => s.isNotEmpty)
                              .toSet().toList()
                            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        }
                        final selected = await _showSearchableDropdown('Select Size', sizes);
                        if (selected != null) {
                          setState(() {
                            _courierProductSize = selected;
                            final normSelectedSize = selected.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
                            if (_courierCategory == 'Alloy') {
                              final matchingAlloy = _alloyCatalog.firstWhere(
                                (t) =>
                                    AlloyCatalogHelper.extractBrand(t).toLowerCase() == brand &&
                                    AlloyCatalogHelper.extractModel(t).toLowerCase() == model &&
                                    AlloyCatalogHelper.extractSize(t).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase() == normSelectedSize,
                                orElse: () => {},
                              );
                              if (matchingAlloy.isNotEmpty) {
                                final price = AlloyCatalogHelper.extractPrice(matchingAlloy);
                                if (price != null) {
                                  _courierProductPriceController.text = price.toStringAsFixed(2);
                                }
                              }
                            } else {
                              final matchingTyre = _tyreCatalog.firstWhere(
                                (t) =>
                                    TyreCatalogHelper.extractBrand(t).toLowerCase() == brand &&
                                    TyreCatalogHelper.extractModel(t).toLowerCase() == model &&
                                    TyreCatalogHelper.extractSize(t).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase() == normSelectedSize,
                                orElse: () => {},
                              );
                              if (matchingTyre.isNotEmpty) {
                                final price = matchingTyre['billing_price'] ?? matchingTyre['basic_price'];
                                if (price != null) {
                                  final numPrice = double.tryParse(price.toString());
                                  _courierProductPriceController.text = numPrice != null ? numPrice.toStringAsFixed(2) : price.toString();
                                }
                              }
                            }
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Size', isDense: true, border: OutlineInputBorder()),
                        child: Text(_courierProductSize ?? 'Select', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _courierProductQtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _courierProductPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Unit Price',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_editingCourierProductIndex != null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cancelEditCourierProduct,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _addCourierProduct,
                        icon: const Icon(Icons.check),
                        label: const Text('Update Product'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _addCourierProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Product'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormLabel(text: 'Additional Package Photos'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _takeCourierPhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take Package Photo'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              if (_courierPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _courierPhotos.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _viewCourierPackagePhoto(i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _courierPhotos[i] is String ? AppCachedImage(imageUrl: _courierPhotos[i], width: 100, height: 100, fit: BoxFit.cover) : Image.file(File(_courierPhotos[i].path), width: 100, height: 100, fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            right: 0, top: 0,
                            child: IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () => setState(() => _courierPhotos.removeAt(i)),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : () => _submitCourierReport(status: AppConstants.statusCompleted),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(widget.draftJob != null ? 'Save Updates' : 'Create Courier Job Card', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (widget.draftJob == null || widget.draftJob?['status'] == AppConstants.statusDraft) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _isLoading ? null : () => _submitCourierReport(status: AppConstants.statusDraft),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save as Draft', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  Future<void> _takeCourierPhoto() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UnlimitedCameraScreen(),
      ),
    );

    if (result != null && result is List<XFile>) {
      setState(() {
        _courierPhotos.addAll(result);
      });
    }
  }

  void _viewCourierPackagePhoto(int photoIndex) {
    showDialog(
      context: context,
      builder: (context) {
        final item = _courierPhotos[photoIndex];
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  InteractiveViewer(
                    child: item is String ? AppCachedImage(imageUrl: item, fit: BoxFit.contain) : Image.file(File(item.path), fit: BoxFit.contain),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _courierPhotos.removeAt(photoIndex);
                  });
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete),
                label: const Text('Delete Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitCourierReport({required String status}) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      _showErrorSnackBar('You are not logged in.');
      return;
    }

    if (_courierNameController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter Customer Name.');
      return;
    }
    
    if (_courierProductsList.isEmpty) {
      _showErrorSnackBar('Please add at least one product before submitting.');
      return;
    }

    if (!await _ensureBranchPrefixConfigured()) {
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> finalProducts = _courierProductsList.map((p) {
        final category = (p['category'] ?? (p['is_alloy'] == true ? 'Alloy' : 'Tyre')).toString();
        return {
          'category': category,
          'is_alloy': category == 'Alloy',
          'brand': p['brand'],
          'model': p['model'],
          'size': p['size'],
          'name': p['name'],
          'price': p['price'],
          'qty': p['qty'],
        };
      }).toList();

      final marksJson = {
        'is_courier': true,
        'products': finalProducts,
        'gst_no': _courierGstController.text.trim(),
        'address': _courierAddressController.text.trim(),
      };

      final int? executiveId = (user['role'] == AppConstants.rolePickupDropoff) ? null : user['id'];
      
      // Ensure branch context is active and valid
      if (!CompanyService().hasActiveCompany) {
        final currentUser = Provider.of<UserProvider>(context, listen: false).user;
        if (currentUser != null) {
          await CompanyService().loadCompaniesForUser(currentUser);
        } else {
          await CompanyService().loadPersistedCompany();
        }
      }
      
      int jobId;
      if (widget.draftJob != null) {
        jobId = widget.draftJob!['id'];
        final Map<String, dynamic> updateData = {
          'marks': jsonEncode(marksJson),
          'Owner name': _courierNameController.text.trim(),
          'client_phone': _courierPhoneController.text.trim(),
          if (status == AppConstants.statusCompleted && widget.draftJob!['status'] == AppConstants.statusDraft) ...{
            'status': AppConstants.statusCompleted,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'started_at': widget.draftJob!['started_at'] ?? DateTime.now().toUtc().toIso8601String(),
          },
        };
        await supabase.from('reports').update(updateData).eq('id', jobId);
      } else {
        final Map<String, dynamic> insertData = {
          'vehicle_id': null, // Explicitly null for couriers
          'executive_id': executiveId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'complaint': jsonEncode(['Courier Dispatch']),
          'status': status, 
          'started_at': status == AppConstants.statusDraft ? null : DateTime.now().toUtc().toIso8601String(),
          'completed_at': status == AppConstants.statusCompleted ? DateTime.now().toUtc().toIso8601String() : null,
          'marks': jsonEncode(marksJson),
          'labour_cost': 0, // Removed labour_cost calculation for Couriers
          'Owner name': _courierNameController.text.trim(),
          'client_phone': _courierPhoneController.text.trim(),
          'company_id': CompanyService().companyId,
          'branch_id': CompanyService().branchId,
          'branch_name': CompanyService().branchName,
          'Guid': CompanyService().guid,
          'company_name': CompanyService().companyName,
        };
        final inserted = await vehicleService.createReport(context, insertData);
        jobId = inserted['id'] as int;
      }

      Map<String, dynamic> productQRs = {};
      for (int i = 0; i < _courierProductsList.length; i++) {
        final images = _courierProductsList[i]['qr_images'] as List<dynamic>? ?? [];
        for (int j = 0; j < images.length; j++) {
          productQRs['product_${i}_qr_$j'] = images[j];
        }
      }

      if (_courierPhotos.isNotEmpty || productQRs.isNotEmpty) {
        _uploadMediaInBackground(
          jobId: jobId,
          wheelPhotos: {},
          vehiclePhotos: List.from(_courierPhotos),
          tyreQRImages: productQRs,
          odometerPhoto: null,
        );
      }

      if (mounted) {
        _showSuccessSnackBar(widget.draftJob != null ? 'Courier Job Card updated successfully!' : 'Courier Job Card created successfully!');
        if (widget.draftJob != null) {
          Navigator.pop(context);
        } else {
          _resetScreen(); // Existing reset form function
          
          // Reset courier fields too
          _courierNameController.clear();
          _courierPhoneController.clear();
          _courierAddressController.clear();
          _courierGstController.clear();
          setState(() {
            _courierProductsList.clear();
            _courierPhotos.clear();
            _isCourierMode = false;
          });
        }
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


}

// Custom Painter for drawing damage marks
class DamagePainter extends CustomPainter {
  final List<Offset> marks;
  DamagePainter({required this.marks});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
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

class SavedRegistrationDraftsScreen extends StatefulWidget {
  final Function(Map<String, dynamic> draft) onSelectDraft;
  const SavedRegistrationDraftsScreen({super.key, required this.onSelectDraft});

  @override
  State<SavedRegistrationDraftsScreen> createState() => _SavedRegistrationDraftsScreenState();
}

class _SavedRegistrationDraftsScreenState extends State<SavedRegistrationDraftsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _drafts = [];

  @override
  void initState() {
    super.initState();
    _fetchDrafts();
  }

  Future<void> _fetchDrafts() async {
    setState(() => _isLoading = true);
    try {
      if (!CompanyService().hasActiveCompany) {
        await CompanyService().loadPersistedCompany();
      }
      final String? companyGuid = CompanyService().guid;

      var query = Supabase.instance.client
          .from('reports')
          .select('*')
          .eq('status', AppConstants.statusDraft);

      if (companyGuid != null && companyGuid.isNotEmpty) {
        query = query.eq('Guid', companyGuid);
      }

      final res = await query.order('created_at', ascending: false);

      final List<Map<String, dynamic>> loaded = [];
      for (var r in (res as List)) {
        final map = Map<String, dynamic>.from(r);
        final marks = map['marks'];
        bool isCourier = false;
        if (marks is String && marks.contains('"is_courier":true')) {
          isCourier = true;
        } else if (marks is Map && marks['is_courier'] == true) {
          isCourier = true;
        }
        if (!isCourier) {
          loaded.add(map);
        }
      }

      if (mounted) {
        setState(() {
          _drafts = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('🔴 Error fetching drafts: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDraft(Map<String, dynamic> draft) async {
    final dynamic rawId = draft['id'];
    final int? id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Draft'),
        content: const Text('Are you sure you want to delete this draft registration?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        try {
          await Supabase.instance.client.from('reports').delete().eq('id', id);
        } catch (e) {
          debugPrint('⚠️ Hard delete failed: $e');
        }

        // Soft delete / cancel status to guarantee removal from Drafts
        await Supabase.instance.client.from('reports').update({
          'status': AppConstants.statusCancelled,
        }).eq('id', id);

        if (mounted) {
          setState(() {
            _drafts.removeWhere((item) {
              final itemRawId = item['id'];
              final itemId = itemRawId is int ? itemRawId : int.tryParse(itemRawId?.toString() ?? '');
              return itemId == id;
            });
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Draft deleted successfully'), backgroundColor: Colors.red),
          );
        }
        await _fetchDrafts();
      } catch (e) {
        debugPrint('🔴 Error deleting draft: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete draft: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Saved Registration Drafts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.drafts_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'No saved registration drafts found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _drafts.length,
                      itemBuilder: (context, index) {
                        final draft = _drafts[index];
                        Map<String, dynamic> marksMap = {};
                        final marks = draft['marks'];
                        if (marks is String) {
                          try { marksMap = jsonDecode(marks); } catch (_) {}
                        } else if (marks is Map) {
                          marksMap = Map<String, dynamic>.from(marks);
                        }

                        final vehicleNo = marksMap['vehicle_number'] ?? draft['Vehicle Number'] ?? draft['vehicles']?['Vehicle Number'] ?? 'Vehicle Registration';
                        final clientName = draft['Owner name'] ?? 'N/A';
                        final phone = draft['client_phone'] ?? 'N/A';
                        final dateStr = draft['created_at'] != null
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(AppDateUtils.parseUtcToLocal(draft['created_at']))
                            : '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade50,
                          child: const Icon(Icons.directions_car, color: Colors.purple),
                        ),
                        title: Text(
                          vehicleNo,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Client: $clientName ($phone)\nSaved: $dateStr',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteDraft(draft),
                              tooltip: 'Delete Draft',
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          widget.onSelectDraft(draft);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
