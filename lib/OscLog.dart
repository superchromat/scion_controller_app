import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'OscWidgetBinding.dart';

final GlobalKey<OscLogTableState> oscLogKey = GlobalKey<OscLogTableState>();

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

class OscLogTable extends StatefulWidget {
  final ValueChanged<Uint8List> onDownload;
  final bool isActive;

  const OscLogTable({
    Key? key,
    required this.onDownload,
    required this.isActive,
  }) : super(key: key);

  @override
  OscLogTableState createState() => OscLogTableState();
}

class OscLogTableState extends State<OscLogTable> {
  final List<OscLogEntry> _entries = [];
  final Set<OscStatus> _filterStatuses = { OscStatus.ok, OscStatus.error, OscStatus.fail };
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;
  int _pendingCount = 0;

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

  void logOscMessage({
    required String address,
    required dynamic arg,
    required OscStatus status,
    required Direction direction,
    required Uint8List binary,
  }) {
    final argsList = (arg is List
        ? arg.map((e) => e.toString())
        : [arg.toString()]);
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

      // if hidden, always scroll; if visible only when already at bottom
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

  Widget _buildCell(
    Widget child,
    int flex, {
    String? tooltip,
    bool isHeader = false,
    String? copyText,
  }) {
    final side = BorderSide(color: Colors.grey[600]!, width: 1);
    final bottom = isHeader
        ? BorderSide(color: Colors.yellow, width: 1)
        : side;

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

    // wrap in copy-on-tap if requested
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
    List<PopupMenuEntry<OscStatus>> statusItems() {
      PopupMenuEntry<OscStatus> item(OscStatus s, String label) {
        return PopupMenuItem<OscStatus>(
          value: s,
          child: Row(
            children: [
              Checkbox(
                value: _filterStatuses.contains(s),
                onChanged: null,
              ),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
            ],
          ),
        );
      }

      return [
        item(OscStatus.ok,    'OK'),
        item(OscStatus.error, 'ERROR'),
        item(OscStatus.fail,  'FAIL'),
      ];
    }

    return Row(children: [
      _buildCell(
        PopupMenuButton<OscStatus>(
          tooltip: 'Filter by status',
          child: Row(
            children: const [
              Text('Status', style: TextStyle(fontFamily: 'Courier', fontSize: 10)),
              Icon(Icons.arrow_drop_down, size: 12),
            ],
          ),
          itemBuilder: (context) => statusItems(),
          onSelected: (s) {
            setState(() {
              if (_filterStatuses.contains(s)) {
                _filterStatuses.remove(s);
              } else {
                _filterStatuses.add(s);
              }
            });
          },
        ),
        1,
        isHeader: true,
      ),
      _buildCell(const Text('Dir', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 1, isHeader: true),
      _buildCell(const Text('Time', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 2, isHeader: true),
      _buildCell(const Text('Address', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 4, isHeader: true),
      _buildCell(const Text('Args', style: TextStyle(fontFamily: 'Courier', fontSize: 10)), 6, isHeader: true),
      _buildCell(const SizedBox(), 1, isHeader: true),
    ]);
  }

  Widget _rowForEntry(OscLogEntry e) {
    // choose a string for each cell we’ll copy
    final statusText = e.status.toString().split('.').last.toUpperCase();
    final dirText    = e.direction == Direction.received ? 'RECEIVED' : 'SENT';
    final timeTextStr = DateFormat('HH:mm:ss.SSS').format(e.timestamp);

    Color statusColor;
    switch (e.status) {
      case OscStatus.ok:    statusColor = Colors.green;  break;
      case OscStatus.error: statusColor = Colors.yellow; break;
      case OscStatus.fail:  statusColor = Colors.red;    break;
    }

    return Row(children: [
      _buildCell(
        Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
        1,
        copyText: statusText,
      ),
      _buildCell(
        Icon(e.direction == Direction.received ? Icons.arrow_forward : Icons.arrow_back, size: 10),
        1,
        copyText: dirText,
      ),
      _buildCell(
        Text(timeTextStr, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
        2,
        copyText: timeTextStr,
      ),
      _buildCell(
        Text(e.address, style: const TextStyle(fontFamily: 'Courier', fontSize: 10), overflow: TextOverflow.ellipsis),
        4,
        tooltip: e.address,
        copyText: e.address,
      ),
      _buildCell(
        Text(e.args, style: const TextStyle(fontFamily: 'Courier', fontSize: 10), overflow: TextOverflow.ellipsis),
        6,
        tooltip: e.args,
        copyText: e.args,
      ),
      _buildCell(
        GestureDetector(onTap: () => widget.onDownload(e.binary), child: const Icon(Icons.download, size: 12)),
        1,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _entries.where((e) => _filterStatuses.contains(e.status)).toList();

    return Column(children: [
      _buildHeader(),
      Expanded(
        child: Stack(children: [
          ListView.builder(
            controller: _scrollController,
            itemCount: visible.length,
            itemBuilder: (_, i) => _rowForEntry(visible[i]),
          ),
          if (!_isAtBottom && _pendingCount > 0)
            Positioned(
              bottom: 0, left: 0, right: 0,
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
