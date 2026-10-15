// lib/services/company_filter_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'company_service.dart';

class CompanyFilterService {
  /// Adds company_name filter to a Supabase query if a company is selected
  /// Returns the modified query builder
  static PostgrestFilterBuilder applyCompanyFilter(
    PostgrestFilterBuilder query, {
    String? companyName,
  }) {
    // If companyName is provided, use it, otherwise get from UserProvider
    final company = companyName ?? _getCurrentCompanyName();
    
    if (company != null && company.isNotEmpty) {
      return query.eq('company_name', company);
    }
    
    return query;
  }
  
  /// Adds company_name filter to a Supabase select query
  static PostgrestFilterBuilder applyCompanyFilterToSelect(
    PostgrestFilterBuilder query, {
    String? companyName,
  }) {
    // If companyName is provided, use it, otherwise get from UserProvider
    final company = companyName ?? _getCurrentCompanyName();
    
    if (company != null && company.isNotEmpty) {
      return query.eq('company_name', company);
    }
    
    return query;
  }
  
  /// Adds company_name to data being inserted/updated
  static Map<String, dynamic> addCompanyToData(
    Map<String, dynamic> data, {
    String? companyName,
  }) {
    // If companyName is provided, use it, otherwise get from UserProvider
    final company = companyName ?? _getCurrentCompanyName();
    
    if (company != null && company.isNotEmpty) {
      final modifiedData = Map<String, dynamic>.from(data);
      modifiedData['company_name'] = company;
      return modifiedData;
    }
    
    return data;
  }
  
  /// Gets the current company name
  static String? getCurrentCompany(BuildContext? context) {
    return CompanyService().companyName;
  }
  
  /// Internal method to get current company name (for use without context)
  static String? _getCurrentCompanyName() {
    return CompanyService().companyName;
  }
  
  /// Validates if data belongs to current company
  static bool isDataForCurrentCompany(
    Map<String, dynamic> data, 
    String? currentCompany
  ) {
    if (currentCompany == null || currentCompany.isEmpty) return true;
    
    final dataCompany = data['company_name'] as String?;
    return dataCompany == currentCompany;
  }
  
  /// Filters a list of data by company name
  static List<Map<String, dynamic>> filterDataByCompany(
    List<Map<String, dynamic>> data,
    String? currentCompany,
  ) {
    if (currentCompany == null || currentCompany.isEmpty) return data;
    
    return data.where((item) {
      final itemCompany = item['company_name'] as String?;
      return itemCompany == currentCompany;
    }).toList();
  }
}
