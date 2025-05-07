import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shared key so other classes can invoke logging
final GlobalKey<OscLogTableState> oscLogKey = GlobalKey<OscLogTableState>();

enum Status { fail, error, ok }
enum Direction { received, sent }

class OscLogEntry {
  final Status status;
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

  /// whether this table is the currently visible page
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
  final Set<Status> _filterStatuses = { Status.ok, Status.error, Status.fail };
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

  /// Call this to append a new OSC message to the log.
  void logOscMessage({
    required String address,
    required dynamic arg,
    required Status status,
    required Direction direction,
    required Uint8List binary,
  }) {
    final argsList =
        (arg is List ? arg.map((e) => e.toString()) : [arg.toString()]);
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

      // if not visible, always scroll; otherwise only if already at bottom
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

  Widget _buildCell(Widget child, int flex,
      {String? tooltip, bool isHeader = false}) {
    final side = BorderSide(color: Colors.grey[600]!, width: 1);
    final bottom = isHeader
        ? BorderSide(color: Colors.yellow, width: 1)
        : side;

    return Flexible(
      flex: flex,
      child: Container(
        height: 12,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(right: side, bottom: bottom),
        ),
        child: DefaultTextStyle.merge(
          style: isHeader
              ? const TextStyle(fontWeight: FontWeight.bold)
              : const TextStyle(),
          child: tooltip != null
              ? Tooltip(message: tooltip, child: child)
              : child,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    List<PopupMenuEntry<Status>> statusItems() {
      PopupMenuEntry<Status> item(Status s, String label) {
        return PopupMenuItem<Status>(
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
        item(Status.ok,    'OK'),
        item(Status.error, 'ERROR'),
        item(Status.fail,  'FAIL'),
      ];
    }

    return Row(children: [
      _buildCell(
        PopupMenuButton<Status>(
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
              if (_filterStatuses.contains(s)) _filterStatuses.remove(s);
              else _filterStatuses.add(s);
            });
          },
        ),
        1,
        isHeader: true,
      ),
      _buildCell(
        const Text('Dir', style: TextStyle(fontFamily: 'Courier', fontSize: 10)),
        1,
        isHeader: true,
      ),
      _buildCell(
        const Text('Time', style: TextStyle(fontFamily: 'Courier', fontSize: 10)),
        2,
        isHeader: true,
      ),
      _buildCell(
        const Text('Address', style: TextStyle(fontFamily: 'Courier', fontSize: 10)),
        4,
        isHeader: true,
      ),
      _buildCell(
        const Text('Args', style: TextStyle(fontFamily: 'Courier', fontSize: 10)),
        6,
        isHeader: true,
      ),
      _buildCell(const SizedBox(), 1, isHeader: true),
    ]);
  }

  Widget _rowForEntry(OscLogEntry e) {
    Color statusColor;
    switch (e.status) {
      case Status.ok:    statusColor = Colors.green; break;
      case Status.error: statusColor = Colors.yellow; break;
      case Status.fail:  statusColor = Colors.red; break;
    }

    final statusDot = Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
    );
    final dirIcon = Icon(
      e.direction == Direction.received ? Icons.arrow_forward : Icons.arrow_back,
      size: 10,
    );

    final timeText = Text(
      DateFormat('HH:mm:ss.SSS a').format(e.timestamp),
      style: const TextStyle(fontFamily: 'Courier', fontSize: 10),
    );

    final addrText = Text(
      e.address,
      style: const TextStyle(fontFamily: 'Courier', fontSize: 10),
      overflow: TextOverflow.ellipsis,
    );

    final argsText = Text(
      e.args,
      style: const TextStyle(fontFamily: 'Courier', fontSize: 10),
      overflow: TextOverflow.ellipsis,
    );

    final downloadBtn = GestureDetector(
      onTap: () => widget.onDownload(e.binary),
      child: const Icon(Icons.download, size: 12),
    );

    return GestureDetector(
      onLongPress: () {
        final line =
            '${e.status} | ${e.direction} | ${DateFormat('HH:mm:ss.SSS a').format(e.timestamp)} | ${e.address} | ${e.args}';
        Clipboard.setData(ClipboardData(text: line));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
        );
      },
      child: Row(children: [
        _buildCell(statusDot, 1),
        _buildCell(dirIcon, 1),
        _buildCell(timeText, 2),
        _buildCell(addrText, 4, tooltip: e.address),
        _buildCell(argsText, 6, tooltip: e.args),
        _buildCell(downloadBtn, 1),
      ]),
    );
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
              bottom: 0,
              left: 0, right: 0,
              child: InkWell(
                onTap: _scrollToBottom,
                child: Container(
                  color: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  child: Text(
                    '$_pendingCount more messages below',
                    style: const TextStyle(fontSize: 10),
                  ),
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
