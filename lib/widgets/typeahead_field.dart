import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TypeaheadOption {
  final String label;
  final String? subtitle;
  final Map<String, dynamic> data;

  const TypeaheadOption({
    required this.label,
    this.subtitle,
    this.data = const {},
  });
}

/// Type-to-filter picker. Shows matching rows as the user types.
/// If the typed value is not in the list, they can create it.
class TypeaheadField extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String hintText;
  final Future<List<TypeaheadOption>> Function(String query) onSearch;
  final void Function(TypeaheadOption option) onSelected;
  final void Function(String query)? onCreateNew;
  final bool allowCreate;
  final bool isDense;
  final Color? accentColor;
  final int maxResults;

  const TypeaheadField({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onSelected,
    this.label,
    this.hintText = 'Type to search...',
    this.onCreateNew,
    this.allowCreate = true,
    this.isDense = true,
    this.accentColor,
    this.maxResults = 40,
  });

  @override
  State<TypeaheadField> createState() => _TypeaheadFieldState();
}

class _TypeaheadFieldState extends State<TypeaheadField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<TypeaheadOption> _options = [];
  bool _loading = false;
  bool _open = false;
  String _lastQuery = '';

  Color get _accent => widget.accentColor ?? AppTheme.primaryColor;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _search(widget.controller.text);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(value));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _open = true;
      _lastQuery = query.trim();
    });
    try {
      final rows = await widget.onSearch(query.trim());
      if (!mounted) return;
      setState(() {
        _options = rows.take(widget.maxResults).toList();
        _loading = false;
        _open = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _options = [];
        _loading = false;
      });
    }
  }

  bool get _canCreate {
    if (!widget.allowCreate || _lastQuery.isEmpty) return false;
    return !_options.any((item) => item.label.toLowerCase() == _lastQuery.toLowerCase());
  }

  void _select(TypeaheadOption option) {
    widget.controller.text = option.label;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: option.label.length),
    );
    widget.onSelected(option);
    setState(() => _open = false);
    _focusNode.unfocus();
  }

  void _create() {
    final query = _lastQuery;
    if (query.isEmpty) return;
    widget.controller.text = query;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    widget.onCreateNew?.call(query);
    setState(() => _open = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        if (mounted && _open) {
          setState(() => _open = false);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            onTap: () {
              if (!_open) {
                _search(widget.controller.text);
              }
            },
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hintText,
              hintStyle: const TextStyle(fontSize: 12),
              isDense: widget.isDense,
              filled: true,
              fillColor: Colors.white,
              suffixIcon: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (_open) {
                    setState(() => _open = false);
                  } else {
                    _search(widget.controller.text);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: _accent,
                    size: 22,
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _accent, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        if (_options.isEmpty && !_canCreate)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'No matching catalog items found.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ),
                        ..._options.map((option) {
                          return InkWell(
                            onTap: () => _select(option),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.8)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if ((option.subtitle ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        option.subtitle!,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (_canCreate)
                          InkWell(
                            onTap: _create,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.add_circle_outline, size: 18, color: _accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Create new “$_lastQuery”',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
