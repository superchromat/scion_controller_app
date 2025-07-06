// lib/osc_log_table.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'osc_widget_binding.dart';

final GlobalKey<OscLogTableState> oscLogKey = GlobalKey<OscLogTableState>();


/// A single entry in the OSC log
class OscLogEntry {
  final OscStatus status;
  final Direction direction;
  final DateTime timestamp;
  final String address;
  final String args;
  final Uint8List binary;

  OscLogEntry({
    required this.status,
    required this.direction,
    required this.timestamp,
    required this.address,
    required this.args,
    required this.binary,
  });
}

/// A table widget that logs OSC messages with filtering and grouping
class OscLogTable extends StatefulWidget {
  final ValueChanged<Uint8List> onDownload;
  final bool isActive;

  const OscLogTable({
    super.key,
    required this.onDownload,
    required this.isActive,
  });

  @override
  OscLogTableState createState() => OscLogTableState();
}

class OscLogTableState extends State<OscLogTable> {
  static const double _toggleAreaWidth = 24.0;
  static const int _maxEntries = 5000;

  final List<OscLogEntry> _entries = [];
  final Set<OscStatus> _filterStatuses = {
    OscStatus.ok,
    OscStatus.error,
    OscStatus.fail,
  };
  final Set<Direction> _filterDirections = {
    Direction.sent,
    Direction.received,
  };

  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;
  int _pendingCount = 0;
  final Set<int> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.offset;
    final atBottom = (pos >= max - 2);
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (_isAtBottom) _pendingCount = 0;
      });
    }
  }

  /// Add a new OSC message to the log
  void logOscMessage({
    required String address,
    required dynamic arg,
    required OscStatus status,
    required Direction direction,
    required Uint8List binary,
  }) {
    final argsList = (arg is List ? arg.map((e) => e.toString()) : [arg.toString()]);
    final entry = OscLogEntry(
      status: status,
      direction: direction,
      timestamp: DateTime.now(),
      address: address,
      args: argsList.join(', '),
      binary: binary,
    );

    setState(() {
      _entries.add(entry);
      if (_entries.length > _maxEntries) {
        _entries.removeRange(0, _entries.length - _maxEntries);
      }
      if (!widget.isActive || _isAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        _pendingCount++;
      }
    });
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _clearAll() {
    setState(() {
      _entries.clear();
      _pendingCount = 0;
      _expandedGroups.clear();
    });
  }

  Widget _buildCell(Widget child, int flex,
      {String? tooltip, bool isHeader = false, String? copyText}) {
    final side = BorderSide(color: Colors.grey[600]!, width: 1);
    final bottom = isHeader ? BorderSide(color: Colors.yellow, width: 1) : side;

    Widget content = Container(
      height: 12,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(border: Border(right: side, bottom: bottom)),
      child: DefaultTextStyle.merge(
        style: isHeader
            ? const TextStyle(fontWeight: FontWeight.bold)
            : const TextStyle(),
        child: tooltip != null ? Tooltip(message: tooltip, child: child) : child,
      ),
    );

    if (copyText != null) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: copyText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(milliseconds: 800),
              ),
            );
          },
          child: content,
        ),
      );
    }

    return Flexible(flex: flex, child: content);
  }

  Widget _buildHeader() {
    // Status filter
    List<PopupMenuEntry<OscStatus>> statusItems() {
      PopupMenuEntry<OscStatus> item(OscStatus s, String label) {
        return PopupMenuItem<OscStatus>(
          value: s,
          child: Row(
            children: [
              Checkbox(value: _filterStatuses.contains(s), onChanged: null),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
            ],
          ),
        );
      }
      return [item(OscStatus.ok, 'OK'), item(OscStatus.error, 'ERROR'), item(OscStatus.fail, 'FAIL')];
    }

    // Direction filter
    List<PopupMenuEntry<Direction>> dirItems() {
      PopupMenuEntry<Direction> item(Direction d, String label) {
        return PopupMenuItem<Direction>(
          value: d,
          child: Row(
            children: [
              Checkbox(value: _filterDirections.contains(d), onChanged: null),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
            ],
          ),
        );
      }
      return [item(Direction.sent, 'SENT'), item(Direction.received, 'RECEIVED')];
    }

    return Row(children: [
      _buildCell(
        PopupMenuButton<OscStatus>(
          tooltip: 'Filter by status',
          child: Row(children: const [Text('Status', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), Icon(Icons.arrow_drop_down, size: 12)]),
          itemBuilder: (c) => statusItems(),
          onSelected: (s) => setState(() => _filterStatuses.contains(s) ? _filterStatuses.remove(s) : _filterStatuses.add(s)),
        ),
        1,
        isHeader: true,
      ),
      _buildCell(
        PopupMenuButton<Direction>(
          tooltip: 'Filter by direction',
          child: Row(children: const [Text('Dir', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), Icon(Icons.arrow_drop_down, size: 12)]),
          itemBuilder: (c) => dirItems(),
          onSelected: (d) => setState(() => _filterDirections.contains(d) ? _filterDirections.remove(d) : _filterDirections.add(d)),
        ),
        1,
        isHeader: true,
      ),
      _buildCell(const Text('Time', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 2, isHeader: true),
      _buildCell(const Text('Address', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 4, isHeader: true),
      _buildCell(const Text('Args', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 6, isHeader: true),
      _buildCell(const SizedBox(), 1, isHeader: true),
    ]);
  }

  /// Single row for one entry
  Widget _rowForEntry(OscLogEntry e) {
    final statusText = e.status.toString().split('.').last.toUpperCase();
    final timeText = DateFormat('HH:mm:ss.SSS').format(e.timestamp);
    Color statusColor;
    switch (e.status) {
      case OscStatus.ok:
        statusColor = Colors.green;
      case OscStatus.error:
        statusColor = Colors.yellow;
      case OscStatus.fail:
        statusColor = Colors.red;
    }
    final iconColor = e.direction == Direction.received ? const Color.fromARGB(255, 156, 204, 243) : const Color.fromARGB(255, 238, 125, 163);
    final icon = Icon(e.direction == Direction.received ? Icons.arrow_forward : Icons.arrow_back, size: 10, color: iconColor);

    return Row(children: [
      _buildCell(Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)), 1, copyText: statusText),
      _buildCell(icon, 1, copyText: e.direction.toString().split('.').last.toUpperCase()),
      _buildCell(Text(timeText, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)), 2, copyText: timeText),
      _buildCell(Text(e.address, style: const TextStyle(fontFamily: 'Courier', fontSize: 10), overflow: TextOverflow.ellipsis), 4, tooltip: e.address, copyText: e.address),
      _buildCell(Text(e.args, style: const TextStyle(fontFamily: 'Courier', fontSize: 10), overflow: TextOverflow.ellipsis), 6, tooltip: e.args, copyText: e.args),
      _buildCell(GestureDetector(onTap: () => widget.onDownload(e.binary), child: const Icon(Icons.download, size: 12)), 1),
    ]);
  }

  /// Summary row when collapsed
  Widget _buildSummaryRow(List<OscLogEntry> group, int gi) {
    final e = group.last;
    return _rowForEntry(e); // reuse single-row styling; grouping indicator is separate
  }

  /// Group toggle column widget
  Widget _buildGroupToggleArea({required bool isSummary, required int groupIndex, int? entryIndex}) {
    if (isSummary) {
      return GestureDetector(
        onTap: () => setState(() => _expandedGroups.add(groupIndex)),
        child: Container(
          width: _toggleAreaWidth,
          height: 12,
          alignment: Alignment.center,
          child: const Icon(Icons.expand, size: 12, color: Colors.yellow),
        ),
      );
    }
    final first = entryIndex == 0;
    return GestureDetector(
      onTap: () => setState(() => _expandedGroups.remove(groupIndex)),
      child: Container(
        width: _toggleAreaWidth,
        height: 12,
        alignment: Alignment.center,
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.yellow, width: 1))),
        child: first ? const Icon(Icons.compress, size: 12, color: Colors.yellow) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // apply filters
    final visible = _entries.where((e) => _filterStatuses.contains(e.status) && _filterDirections.contains(e.direction)).toList();
    // group by address
    final List<List<OscLogEntry>> groups = [];
    for (var i = 0; i < visible.length;) {
      var j = i + 1;
      while (j < visible.length && visible[j].address == visible[i].address) {
        j++;
      }
      groups.add(visible.sublist(i, j));
      i = j;
    }

    return Column(children: [
      Row(
        children: [
          const Spacer(),
          TextButton(onPressed: _clearAll, child: const Text('Clear All')),
        ],
      ),
      Row(children: [const SizedBox(width: _toggleAreaWidth), Expanded(child: _buildHeader())]),
      Expanded(
        child: Stack(children: [
          ListView.builder(
            controller: _scrollController,
            itemCount: groups.length,
            itemBuilder: (_, gi) {
              final group = groups[gi];
              final collapsed = group.length > 1 && !_expandedGroups.contains(gi);
              if (collapsed) {
                return Row(children: [_buildGroupToggleArea(isSummary: true, groupIndex: gi), Expanded(child: _buildSummaryRow(group, gi))]);
              }
              if (group.length > 1 && _expandedGroups.contains(gi)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var ei = 0; ei < group.length; ei++)
                      Row(children: [
                        _buildGroupToggleArea(isSummary: false, groupIndex: gi, entryIndex: ei),
                        Expanded(child: _rowForEntry(group[ei])),
                      ]),
                  ],
                );
              }
              return Row(children: [const SizedBox(width: _toggleAreaWidth), Expanded(child: _rowForEntry(group.first))]);
            },
          ),
          if (!_isAtBottom && _pendingCount > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: InkWell(
                onTap: _scrollToBottom,
                child: Container(
                  color: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  child: Text('$_pendingCount more messages below', style: const TextStyle(fontSize: 10)),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
