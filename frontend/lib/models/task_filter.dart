class TaskFilter {
  final String? courseId;
  final String? status;
  final DateTime? startDate;
  final DateTime? endDate;

  const TaskFilter({
    this.courseId,
    this.status,
    this.startDate,
    this.endDate,
  });

  TaskFilter copyWith({
    String? courseId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return TaskFilter(
      courseId: courseId ?? this.courseId,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  String toQueryString() {
    final params = <String>[];
    
    if (courseId != null && courseId!.isNotEmpty) {
      params.add('course_id=$courseId');
    }
    if (status != null && status!.isNotEmpty) {
      params.add('status=$status');
    }
    if (startDate != null) {
      params.add('start_date=${startDate!.toIso8601String()}');
    }
    if (endDate != null) {
      params.add('end_date=${endDate!.toIso8601String()}');
    }
    
    return params.isEmpty ? '' : '?${params.join('&')}';
  }

  bool get isActive {
    return (courseId != null && courseId!.isNotEmpty) ||
        (status != null && status!.isNotEmpty) ||
        startDate != null ||
        endDate != null;
  }

  TaskFilter clear() {
    return const TaskFilter();
  }
}
