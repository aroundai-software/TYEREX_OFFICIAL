
// lib/services/client_features_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientFeaturesService {
  static final ClientFeaturesService _instance = ClientFeaturesService._internal();
  factory ClientFeaturesService() => _instance;
  ClientFeaturesService._internal();

  final supabase = Supabase.instance.client;

  /// Checks if a specific global feature is enabled for the app.
  /// This is universal and not tied to any company or logged-in status.
  Future<bool> checkFeatureStatus(String featureName) async {
    try {
      final response = await supabase
          .from('client_features')
          .select('is_active')
          .eq('feature_name', featureName)
          .maybeSingle();

      if (response == null) {
        // The table MUST contain the universal record. Insert it if it's missing.
        try {
          await supabase.from('client_features').insert({
            'feature_name': featureName,
            'is_active': true,
          });
          debugPrint('✅ Inserted missing universal feature record for $featureName');
        } catch (insertError) {
          debugPrint('⚠️ Could not insert missing universal feature record: $insertError');
        }
        return true;
      }

      final dynamic featureValue = response['is_active'];
      if (featureValue is bool) {
        return featureValue;
      } else if (featureValue is String) {
        return featureValue.toLowerCase() == 'true';
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Error checking universal feature status for $featureName: $e');
      // If table doesn't exist or network error, fail open (allow access)
      return true;
    }
  }
}
