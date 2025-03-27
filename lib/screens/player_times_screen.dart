import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/format_time.dart';
import '../widgets/resizable_container.dart';

class PlayerTimesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        var session = appState.session;
        var players = session.players.entries
            .map((entry) => MapEntry(entry.key, entry.value))
            .toList()
            .asMap()
            .entries
            .toList();
        players.sort((a, b) {
          var timeA = a.value.value.active && !session.isPaused
              ? a.value.value.totalTime +
                  (session.matchTime - (a.value.value.lastActiveMatchTime ?? session.matchTime))
              : a.value.value.totalTime;
          var timeB = b.value.value.active && !session.isPaused
              ? b.value.value.totalTime +
                  (session.matchTime - (b.value.value.lastActiveMatchTime ?? session.matchTime))
              : b.value.value.totalTime;
          if (timeB != timeA) return timeB.compareTo(timeA);
          return session.currentOrder.indexOf(a.value.key).compareTo(session.currentOrder.indexOf(b.value.key));
        });

        return Scaffold(
          appBar: AppBar(
            title: Text('Player Times'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ResizableContainer(
              initialHeight: 450,
              minHeight: 200,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              handleOnTop: true,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Player', style: TextStyle(fontSize: 16, color: Colors.white))),
                    DataColumn(label: Text('Time', style: TextStyle(fontSize: 16, color: Colors.white))),
                  ],
                  rows: players.map((entry) {
                    var name = entry.value.key;
                    var player = entry.value.value;
                    var time = player.active && !session.isPaused && player.lastActiveMatchTime != null
                        ? player.totalTime +
                            (session.matchTime - player.lastActiveMatchTime!)
                        : player.totalTime;
                    return DataRow(
                      cells: [
                        DataCell(Text(name, style: TextStyle(fontSize: 16, color: Colors.white))),
                        DataCell(Text(formatTime(time), style: TextStyle(fontSize: 16, color: Colors.white))),
                      ],
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (player.active) return Colors.green.withValues(alpha: 51); // 0.2 opacity
                        if (session.enableTargetDuration && time >= session.targetPlayDuration) {
                          return Colors.yellow.withValues(alpha: 51); // 0.2 opacity
                        }
                        return Colors.red.withValues(alpha: 51); // 0.2 opacity
                      }),
                    );
                  }).toList(),
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  headingRowHeight: 48,
                  columnSpacing: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 5,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
} 