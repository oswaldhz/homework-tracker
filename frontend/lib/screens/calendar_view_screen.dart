import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/task.dart';

class CalendarViewScreen extends StatefulWidget {
  final List<Task> tasks;
  final Function(Task) onTaskTap;
  final Function(Task) onToggleComplete;

  const CalendarViewScreen({
    super.key,
    required this.tasks,
    required this.onTaskTap,
    required this.onToggleComplete,
  });

  @override
  State<CalendarViewScreen> createState() => _CalendarViewScreenState();
}

class _CalendarViewScreenState extends State<CalendarViewScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<Task>> _getEventsForMonth() {
    Map<DateTime, List<Task>> events = {};
    
    for (var task in widget.tasks) {
      if (task.dueDate != null) {
        final dateKey = DateTime(
          task.dueDate!.year,
          task.dueDate!.month,
          task.dueDate!.day,
        );
        
        if (!events.containsKey(dateKey)) {
          events[dateKey] = [];
        }
        events[dateKey]!.add(task);
      }
    }
    
    return events;
  }

  List<Task> _getTasksForDay(DateTime day) {
    final events = _getEventsForMonth();
    final dateKey = DateTime(day.year, day.month, day.day);
    return events[dateKey] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final events = _getEventsForMonth();
    final selectedTasks = _selectedDay != null ? _getTasksForDay(_selectedDay!) : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar View'),
      ),
      body: Column(
        children: [
          TableCalendar<Task>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            eventLoader: (day) {
              final dateKey = DateTime(day.year, day.month, day.day);
              return events[dateKey] ?? [];
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return null;
                
                return Positioned(
                  bottom: 1,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: events.take(3).map((task) {
                        Color color;
                        if (task.isOverdue) {
                          color = Colors.red;
                        } else if (task.isDueSoon) {
                          color = Colors.orange;
                        } else if (task.isCompleted) {
                          color = Colors.green;
                        } else {
                          color = Theme.of(context).colorScheme.primary;
                        }
                        
                        return Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              defaultBuilder: (context, day, _) {
                final tasks = _getTasksForDay(day);
                if (tasks.isEmpty) return null;
                
                return Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: tasks.take(2).map((task) {
                      return Text(
                        task.title.length > 15 
                            ? '${task.title.substring(0, 15)}...' 
                            : task.title,
                        style: TextStyle(
                          fontSize: 8,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(8),
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(8),
              ),
              todayTextStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              selectedTextStyle: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              cellPadding: const EdgeInsets.all(2),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonShowsNext: false,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: selectedTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedDay != null
                              ? 'No tasks for this day'
                              : 'Select a day to view tasks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: selectedTasks.length,
                    itemBuilder: (context, index) {
                      final task = selectedTasks[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Checkbox(
                            value: task.isCompleted,
                            onChanged: (_) => widget.onToggleComplete(task),
                          ),
                          title: Text(
                            task.title,
                            style: TextStyle(
                              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.courseName),
                              Text(
                                task.dueDateFormatted,
                                style: TextStyle(
                                  color: task.isOverdue
                                      ? Colors.red
                                      : task.isDueSoon
                                          ? Colors.orange
                                          : null,
                                  fontWeight: task.isOverdue || task.isDueSoon
                                      ? FontWeight.w600
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => widget.onTaskTap(task),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
