class _Sentinel {
  const _Sentinel();
}

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

  static const _sentinel = _Sentinel();

  TaskFilter copyWith({
    Object? courseId = _sentinel,
    Object? status = _sentinel,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
  }) {
    return TaskFilter(
      courseId: courseId is _Sentinel ? this.courseId : courseId as String?,
      status: status is _Sentinel ? this.status : status as String?,
      startDate: startDate is _Sentinel ? this.startDate : startDate as DateTime?,
      endDate: endDate is _Sentinel ? this.endDate : endDate as DateTime?,
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
