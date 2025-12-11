import 'package:flutter/material.dart';

import 'auth_store.dart';
import 'models/call_log.dart';
import 'widgets/call_log_item.dart';
import 'call_page.dart';
import 'services/call_log_service.dart';

/// Call History Screen
/// Displays call logs with filtering and search functionality
class CallHistoryScreen extends StatefulWidget {
  final TextEditingController? searchController;
  final String? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  
  const CallHistoryScreen({
    super.key,
    this.searchController,
    this.searchQuery,
    this.onSearchChanged,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLog> _allCallLogs = [];
  List<CallLog> _filteredCallLogs = [];
  bool _loading = true;
  String? _error;
  CallFilter _currentFilter = CallFilter.all;
  late TextEditingController _searchController;
  String _searchQuery = '';
  Map<String, dynamic>? _me;
  final Map<String, dynamic> _idMap = {};
  int get _allCount => _allCallLogs.length;
  int get _outgoingCount =>
      _allCallLogs.where((l) => l.type == CallType.outgoing).length;
  int get _incomingCount =>
      _allCallLogs.where((l) => l.type == CallType.incoming).length;

  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController ?? TextEditingController();
    _searchQuery = widget.searchQuery ?? '';
    _loadCallHistory();
    _loadProfile();
  }
  
  @override
  void didUpdateWidget(CallHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      _applyFilters();
    }
  }

  @override
  void dispose() {
    if (widget.searchController == null) {
    _searchController.dispose();
    }
    super.dispose();
  }

  /// Load user profile
  Future<void> _loadProfile() async {
    try {
      final user = await AuthStore.getUser();
      if (user != null) {
        setState(() => _me = user);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  /// Load call history from local storage
  Future<void> _loadCallHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load from local storage (SharedPreferences)
      final logs = await CallLogService.getCallLogs();
      
      setState(() {
        _allCallLogs = logs;
        _loading = false;
      });

      _applyFilters();
    } catch (e) {
      setState(() {
        _error = 'Failed to load call history: $e';
        _loading = false;
      });
    }
  }

  /// Apply current filter and search query
  void _applyFilters() {
    List<CallLog> filtered = List.from(_allCallLogs);

    // Apply filter
    switch (_currentFilter) {
      case CallFilter.missed:
        filtered = filtered.where((log) => log.status == CallStatus.missed).toList();
        break;
      case CallFilter.outgoing:
        filtered = filtered.where((log) => log.type == CallType.outgoing).toList();
        break;
      case CallFilter.incoming:
        filtered = filtered.where((log) => log.type == CallType.incoming).toList();
        break;
      case CallFilter.all:
        break;
    }

    // Apply search
    final searchQuery = widget.searchQuery ?? _searchQuery;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((log) {
        final name = log.getDisplayName().toLowerCase();
        final email = (log.peerEmail ?? '').toLowerCase();
        return name.contains(query) || email.contains(query);
      }).toList();
    }

    setState(() {
      _filteredCallLogs = filtered;
    });
  }

  /// Group call logs by date
  Map<String, List<CallLog>> _groupByDate(List<CallLog> logs) {
    final Map<String, List<CallLog>> grouped = {};
    
    for (final log in logs) {
      final date = log.startTime;
      String key;
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final dateOnly = DateTime(date.year, date.month, date.day);
      
      if (dateOnly == today) {
        key = 'Today';
      } else if (dateOnly == yesterday) {
        key = 'Yesterday';
      } else {
        // Format as "Month Day, Year" or "Month Day" if current year
        if (date.year == now.year) {
          key = '${_getMonthName(date.month)} ${date.day}';
        } else {
          key = '${_getMonthName(date.month)} ${date.day}, ${date.year}';
        }
      }
      
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(log);
    }
    
    // Sort logs within each group by time (newest first)
    grouped.forEach((key, value) {
      value.sort((a, b) => b.startTime.compareTo(a.startTime));
    });
    
    return grouped;
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  /// Start a new call
  Future<void> _startCall(CallLog? log, bool isVideo) async {
    if (log == null) {
      // Show dialog to select contact
      final emailController = TextEditingController();
      final email = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isVideo ? 'Start Video Call' : 'Start Call'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Enter email',
              prefixIcon: Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, emailController.text.trim());
              },
              child: const Text('Call'),
            ),
          ],
        ),
      );
      
      if (email != null && email.isNotEmpty) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallPage(
              peerId: email, // This should be user ID, not email
              peerName: email,
              outgoing: true,
              video: isVideo,
            ),
          ),
        );
      }
      return;
    }

    // Call the same person again
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(
          peerId: log.peerId,
          peerName: log.getDisplayName(),
          outgoing: true,
          video: isVideo ? log.isVideoCall : false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface, // Use theme surface color
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: _buildChipsRow(colorScheme),
          ),
          Expanded(
            child: _buildCallLogsList(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildChipsRow(ColorScheme colorScheme) {
    Widget pill(String label, int count, CallFilter filter) {
      final selected = _currentFilter == filter;
      final bg = colorScheme.primary; // Use theme primary color
      final textColor = colorScheme.onPrimary; // Use theme onPrimary color
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: () {
            setState(() => _currentFilter = filter);
            _applyFilters();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? bg : bg.withOpacity(0.6),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count > 0 ? '$label ($count)' : label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          pill('All', _allCount, CallFilter.all),
          pill('Outgoing', _outgoingCount, CallFilter.outgoing),
          pill('Incoming', _incomingCount, CallFilter.incoming),
        ],
      ),
    );
  }

  Widget _buildCallLogsList(ColorScheme colorScheme) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: colorScheme.primary, // Use theme primary color
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadCallHistory,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredCallLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.call_end,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _allCallLogs.isEmpty
                  ? 'No call history'
                  : 'No calls match your filter',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a call to see it here',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped = _groupByDate(_filteredCallLogs);
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        // Sort: Today, Yesterday, then by date
        if (a == 'Today') return -1;
        if (b == 'Today') return 1;
        if (a == 'Yesterday') return -1;
        if (b == 'Yesterday') return 1;
        return b.compareTo(a); // For dates, newer first
      });

    return RefreshIndicator(
      onRefresh: _loadCallHistory,
      backgroundColor: colorScheme.surface,
      color: colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: sortedKeys.length,
        itemBuilder: (context, index) {
          final dateKey = sortedKeys[index];
          final logs = grouped[dateKey]!;
          final isToday = dateKey == 'Today';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Row(
                  children: [
                    Text(
                      dateKey,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant, // Use theme color
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.primary, // Use theme primary color
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...logs.map((log) => CallLogItem(
                    callLog: log,
                    onTap: () {},
                    onCallTap: () => _startCall(log, log.isVideoCall),
                  )),
            ],
          );
        },
      ),
    );
  }
}

