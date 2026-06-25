import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/moodle_service.dart';
import 'task_materials_screen.dart';
import 'file_upload_screen.dart';
import 'quiz_screen.dart';

class TaskDetailScreen extends StatelessWidget {
  final Task task;
  final VoidCallback onToggleComplete;

  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.onToggleComplete,
  });

  Future<void> _openUrl(BuildContext context) async {
    if (task.url == null || task.url!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No URL available for this task')),
      );
      return;
    }

    final uri = Uri.parse(task.url!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: ${task.url}')),
        );
      }
    }
  }

  Future<void> _handleToggleComplete(BuildContext context) async {
    final api = context.read<ApiService>();
    final result = await api.toggleComplete(task.id);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Task updated'),
          backgroundColor: result['success'] == true
              ? (result['synced'] == true ? Colors.green : Colors.orange)
              : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      
      Navigator.pop(context);
    }
  }

  bool get _isAssignment => task.url?.contains('/mod/assign/') ?? false;
  bool get _isQuiz => task.url?.contains('/mod/quiz/') ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = task.isOverdue;
    final isDueSoon = task.isDueSoon;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: [
          IconButton(
            icon: Icon(
              task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: task.isCompleted ? Colors.green : null,
            ),
            onPressed: () => _handleToggleComplete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              task.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOverdue
                    ? Colors.red.withOpacity(0.1)
                    : isDueSoon
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOverdue
                      ? Colors.red
                      : isDueSoon
                          ? Colors.orange
                          : Colors.green,
                ),
              ),
              child: Text(
                isOverdue
                    ? 'Overdue'
                    : isDueSoon
                        ? 'Due Soon'
                        : task.isCompleted
                            ? 'Completed'
                            : 'Pending',
                style: TextStyle(
                  color: isOverdue
                      ? Colors.red
                      : isDueSoon
                          ? Colors.orange
                          : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Course info
            _InfoCard(
              icon: Icons.school,
              label: 'Course',
              child: Text(
                task.courseName,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),

            // Due date
            _InfoCard(
              icon: Icons.calendar_today,
              label: 'Due Date',
              child: Text(
                task.dueDateFormatted,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isOverdue
                      ? Colors.red
                      : isDueSoon
                          ? Colors.orange
                          : null,
                  fontWeight: isOverdue || isDueSoon ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Description
            if (task.description != null && task.description!.isNotEmpty) ...[
              Text(
                'Description',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  task.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Find Related Materials button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskMaterialsScreen(task: task),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Find Related Materials'),
              ),
            ),
            const SizedBox(height: 12),

            // Upload Homework button - only for assignments
            if (_isAssignment) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FileUploadScreen(task: task),
                      ),
                    );
                    if (context.mounted) {
                      final fresh = context.read<ApiService>().tasks.where((t) => t.id == task.id).firstOrNull;
                      if (fresh != null && (fresh.submissionFiles.isNotEmpty || fresh.isSubmitted || result == true)) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TaskDetailScreen(
                              task: fresh,
                              onToggleComplete: onToggleComplete,
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Homework'),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Answer Quiz button - only for quizzes
            if (_isQuiz) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QuizScreen(task: task),
                      ),
                    );
                  },
                  icon: const Icon(Icons.quiz),
                  label: const Text('Answer Quiz'),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Open in Moodle button
            if (task.url != null && task.url!.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openUrl(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in Moodle'),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Submission Info Section
            if (task.fileUploaded || task.isSubmitted || task.submissionFiles.isNotEmpty || task.quizGrade != null) ...[
              const SizedBox(height: 24),
              Text(
                'Submission Status',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Assignment submission info
                      if (task.submissionFiles.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.description, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Uploaded Files',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...task.submissionFiles.map((file) => _buildFileInfoCard(context, file)),
                        const SizedBox(height: 16),
                      ],
                      
                      // Quiz grade info
                      if (task.quizGrade != null) ...[
                        Row(
                          children: [
                            Icon(Icons.grade, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              'Quiz Score',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Grade: ${task.quizGrade!.toStringAsFixed(1)}%',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[800],
                                ),
                              ),
                              if (task.quizFeedback != null && task.quizFeedback!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Feedback: ${task.quizFeedback!}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                              if (task.lastSubmissionCheck != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Last checked: ${_formatDate(task.lastSubmissionCheck!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Submission status text
                      if (task.submissionStatus != null && task.submissionStatus!.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task.submissionStatus!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Sync button for assignments
                      if (_isAssignment) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _syncSubmissionStatus(context),
                            icon: const Icon(Icons.sync),
                            label: const Text('Sync with Moodle'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 24),

            // Toggle complete button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _handleToggleComplete(context),
                icon: Icon(
                  task.isCompleted ? Icons.undo : Icons.check,
                ),
                label: Text(
                  task.isCompleted ? 'Mark as Pending' : 'Mark as Complete',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFileInfoCard(BuildContext context, Map<String, dynamic> file) {
    final theme = Theme.of(context);
    final filename = file['filename'] as String? ?? 'Unknown file';
    final size = file['size'] as int? ?? 0;
    final uploadedAt = file['uploaded_at'] as String?;
    final itemid = file['itemid'] as int?;
    final fileUrl = file['url'] as String?;
    final fileUrlValid = fileUrl != null && fileUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (fileUrlValid) {
                _launchUrl(fileUrl);
              } else if (task.url != null) {
                _launchUrl(task.url!);
              }
            },
            child: Icon(
              _getFileIcon(filename.split('.').last),
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (fileUrlValid) {
                  _launchUrl(fileUrl);
                } else if (task.url != null) {
                  _launchUrl(task.url!);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: fileUrlValid || task.url != null ? theme.colorScheme.primary : null,
                      decoration: fileUrlValid || task.url != null ? TextDecoration.underline : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatFileSize(size)}  •  ${uploadedAt != null ? _formatDate(DateTime.parse(uploadedAt)) : 'Unknown date'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          if (fileUrlValid || task.url != null)
            IconButton(
              icon: Icon(Icons.open_in_new, color: theme.colorScheme.primary, size: 20),
              tooltip: fileUrlValid ? 'Open file' : 'Open in Moodle',
              onPressed: () => _launchUrl(fileUrlValid ? fileUrl : task.url!),
            ),
          if (itemid != null && !fileUrlValid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ID: $itemid',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
  
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  Future<void> _syncSubmissionStatus(BuildContext context) async {
    final api = context.read<ApiService>();
    final cred = await DatabaseService.instance.getCredentials();
    if (cred == null) return;
    
    final username = await AuthService.instance.decrypt(cred['encrypted_username'] as String);
    final password = await AuthService.instance.decrypt(cred['encrypted_password'] as String);
    final loginType = cred['login_type'] as String? ?? 'moodle';
    final sessionCookie = loginType == 'office365' ? password : null;
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Syncing with Moodle...'), duration: Duration(seconds: 2)),
      );
    }
    
    try {
      // Try to fetch updated submission status
      await MoodleService.instance.checkSubmissionStatus(
        cred['moodle_url'] as String,
        username,
        password,
        task.url!,
        sessionCookie: sessionCookie,
      );
      
      // Refresh task data
      await api.fetchTasks();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced with Moodle'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
