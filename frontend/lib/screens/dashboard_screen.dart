import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../providers/theme_provider.dart';
import '../models/task.dart';
import '../widgets/task_card.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../screens/task_detail_screen.dart';
import '../screens/calendar_view_screen.dart';
import '../screens/login_screen.dart';
import '../screens/settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _weekOnly = false;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final api = context.read<ApiService>();
    await Future.wait([
      api.fetchTasks(weekOnly: _weekOnly),
      api.fetchStats(),
      api.fetchCourses(),
    ]);
    _checkDueSoonNotifications();
  }

  void _checkDueSoonNotifications() {
    final api = context.read<ApiService>();
    for (final task in api.tasks) {
      if (task.isDueSoon) {
        NotificationService.instance.showDueSoonNotification(
          task.title,
          task.dueDateFormatted,
        );
      } else if (task.isOverdue) {
        NotificationService.instance.showOverdueNotification(
          task.title,
          task.dueDateFormatted,
        );
      }
    }
  }

  void _navigateToTaskDetail(Task task) {
    final api = context.read<ApiService>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskDetailScreen(
          task: task,
          onToggleComplete: () async {
            await api.toggleComplete(task.id);
          },
        ),
      ),
    );
  }

  void _navigateToCalendarView() {
    final api = context.read<ApiService>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CalendarViewScreen(
          tasks: api.tasks,
          onTaskTap: _navigateToTaskDetail,
          onToggleComplete: (task) async {
            final api = context.read<ApiService>();
            await api.toggleComplete(task.id);
          },
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const FilterBottomSheet(),
    );
  }

  List<Task> _filterTasks(List<Task> tasks, int tabIndex) {
    switch (tabIndex) {
      case 0:
        return tasks.where((t) => !t.isCompleted && !t.isOverdue).toList();
      case 1:
        return tasks.where((t) => t.isCompleted).toList();
      case 2:
        return tasks.where((t) => t.isOverdue).toList();
      default:
        return tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final themeProvider = context.watch<ThemeProvider>();
    final stats = api.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homework Tracker'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: 'Toggle theme',
            onPressed: () {
              final newMode = themeProvider.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              themeProvider.setThemeMode(newMode);
            },
          ),
          IconButton(
            icon: Icon(_weekOnly ? Icons.calendar_month : Icons.view_list),
            tooltip: _weekOnly ? 'Showing this week' : 'Showing all',
            onPressed: () {
              setState(() => _weekOnly = !_weekOnly);
              api.fetchTasks(weekOnly: _weekOnly);
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_view_day),
            tooltip: 'Calendar view',
            onPressed: _navigateToCalendarView,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final success = await api.refresh();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Refreshed!' : 'Refresh failed')),
                );
              }
            },
          ),
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'logout') {
                await api.logout();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Pending (${stats['pending'] ?? 0})'),
            Tab(text: 'Done (${stats['completed'] ?? 0})'),
            Tab(text: 'Overdue'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildStatsBar(stats),
          if (api.filter.isActive)
            _buildFilterChip(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [0, 1, 2].map((i) => _buildTaskList(api, i)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(Map<String, int> stats) {
    final overdueCount = stats['overdue'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _StatChip(label: 'Total', value: stats['total'] ?? 0, color: Colors.blue),
          const SizedBox(width: 8),
          _StatChip(label: 'Done', value: stats['completed'] ?? 0, color: Colors.green),
          const SizedBox(width: 8),
          _StatChip(label: 'Due Soon', value: stats['due_soon'] ?? 0, color: Colors.orange),
          if (overdueCount > 0) ...[
            const SizedBox(width: 8),
            _OverdueChip(count: overdueCount),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip() {
    final api = context.watch<ApiService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 16),
          const SizedBox(width: 8),
          const Text('Active filters:'),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (api.filter.courseId != null)
                    _FilterChip(
                      label: 'Course',
                      onDeleted: () {
                        api.setFilter(api.filter.copyWith(courseId: null));
                      },
                    ),
                  if (api.filter.status != null)
                    _FilterChip(
                      label: 'Status: ${api.filter.status}',
                      onDeleted: () {
                        api.setFilter(api.filter.copyWith(status: null));
                      },
                    ),
                  if (api.filter.startDate != null)
                    _FilterChip(
                      label: 'From: ${api.filter.startDate!.day}/${api.filter.startDate!.month}',
                      onDeleted: () {
                        api.setFilter(api.filter.copyWith(startDate: null));
                      },
                    ),
                  if (api.filter.endDate != null)
                    _FilterChip(
                      label: 'To: ${api.filter.endDate!.day}/${api.filter.endDate!.month}',
                      onDeleted: () {
                        api.setFilter(api.filter.copyWith(endDate: null));
                      },
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => api.clearFilter(),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(ApiService api, int tabIndex) {
    if (api.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filterTasks(api.tasks, tabIndex);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              tabIndex == 0 ? 'No pending tasks!' : tabIndex == 1 ? 'No completed tasks yet' : 'No overdue tasks!',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final task = filtered[index];
          return TaskCard(
            task: task,
            onTap: () => _navigateToTaskDetail(task),
            onToggleComplete: () async {
              final result = await api.toggleComplete(task.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Task updated'),
                    backgroundColor: result['success'] == true
                        ? (result['synced'] == true ? Colors.green : Colors.orange)
                        : Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}

class _OverdueChip extends StatelessWidget {
  final int count;

  const _OverdueChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                Text('$count', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
            const Text('Overdue', style: TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const _FilterChip({required this.label, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: Icon(
              Icons.close,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
