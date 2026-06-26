import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggleComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = task.isOverdue;
    final isDueSoon = task.isDueSoon;

    Color borderColor;
    Color? backgroundColor;
    if (isOverdue) {
      borderColor = Colors.red;
      backgroundColor = Colors.red.withValues(alpha: 0.05);
    } else if (isDueSoon) {
      borderColor = Colors.orange;
      backgroundColor = Colors.orange.withValues(alpha: 0.05);
    } else {
      borderColor = theme.colorScheme.outlineVariant;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: borderColor, width: isOverdue || isDueSoon ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: task.isCompleted,
                    onChanged: (_) => onToggleComplete(),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: task.isCompleted
                                      ? theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5)
                                      : null,
                                ),
                              ),
                            ),
                            // Submission status icons
                            if (task.fileUploaded || task.isSubmitted) ...[
                              const Icon(
                                Icons.cloud_done,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (task.quizGrade != null) ...[
                              const Icon(
                                Icons.grade,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (isOverdue)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'OVERDUE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.book,
                                  size: 14, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  task.courseName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: isOverdue
                                  ? Colors.red
                                  : isDueSoon
                                      ? Colors.orange
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.dueDateFormatted,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isOverdue
                                    ? Colors.red
                                    : isDueSoon
                                        ? Colors.orange
                                        : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isOverdue || isDueSoon
                                    ? FontWeight.w600
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (task.description != null && task.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  task.description!.length > 150
                      ? '${task.description!.substring(0, 150)}...'
                      : task.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
