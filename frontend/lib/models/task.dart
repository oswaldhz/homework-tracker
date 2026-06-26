import 'dart:convert';

class Task {
  final int id;
  final String title;
  final String courseName;
  final DateTime? dueDate;
  final String status;
  final bool isCompleted;
  final bool fileUploaded;
  final bool isSubmitted;
  final List<Map<String, dynamic>> submissionFiles;
  final String? submissionStatus;
  final double? quizGrade;
  final String? quizFeedback;
  final DateTime? lastSubmissionCheck;
  final String? url;
  final String? description;

  Task({
    required this.id,
    required this.title,
    required this.courseName,
    this.dueDate,
    required this.status,
    required this.isCompleted,
    this.fileUploaded = false,
    this.isSubmitted = false,
    this.submissionFiles = const [],
    this.submissionStatus,
    this.quizGrade,
    this.quizFeedback,
    this.lastSubmissionCheck,
    this.url,
    this.description,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> files = [];
    try {
      if (json['submission_files'] != null && json['submission_files'].toString().isNotEmpty) {
        files = List<Map<String, dynamic>>.from(jsonDecode(json['submission_files'] as String));
      }
    } catch (_) {}

    return Task(
      id: json['id'] as int,
      title: json['title'] as String,
      courseName: json['course_name'] as String,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      status: json['status'] as String,
      isCompleted: json['is_completed'] is bool
          ? json['is_completed'] as bool
          : (json['is_completed'] as int? ?? 0) == 1,
      fileUploaded: (json['file_uploaded'] as int? ?? 0) == 1,
      isSubmitted: (json['is_submitted'] as int? ?? 0) == 1,
      submissionFiles: files,
      submissionStatus: json['submission_status'] as String?,
      quizGrade: (json['quiz_grade'] as num?)?.toDouble(),
      quizFeedback: json['quiz_feedback'] as String?,
      lastSubmissionCheck: json['last_submission_check'] != null 
          ? DateTime.parse(json['last_submission_check'] as String) 
          : null,
      url: json['url'] as String?,
      description: json['description'] as String?,
    );
  }

  bool get isOverdue {
    if (dueDate == null) return false;
    return dueDate!.isBefore(DateTime.now()) && !isCompleted;
  }

  bool get isDueSoon {
    if (dueDate == null) return false;
    final diff = dueDate!.difference(DateTime.now());
    return diff.inHours > 0 && diff.inHours <= 24 && !isCompleted;
  }

  String get dueDateFormatted {
    if (dueDate == null) return 'No due date';
    final now = DateTime.now();
    final diff = dueDate!.difference(now);

    if (diff.isNegative) {
      return 'Overdue by ${-diff.inDays}d';
    } else if (diff.inDays == 0) {
      return 'Today at ${dueDate!.hour}:${dueDate!.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Tomorrow';
    } else if (diff.inDays < 7) {
      return 'In ${diff.inDays} days';
    } else {
      return '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}';
    }
  }
}
