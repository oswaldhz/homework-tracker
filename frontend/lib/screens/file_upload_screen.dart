import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/moodle_service.dart';

class FileUploadScreen extends StatefulWidget {
  final Task task;

  const FileUploadScreen({super.key, required this.task});

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  PlatformFile? _selectedFile;
  bool _uploading = false;
  bool _syncing = false;
  bool _removing = false;
  String? _statusMessage;
  bool _uploadSuccess = false;
  bool _openInBrowser = false;
  String? _browserUrl;
  String? _uploadedFileUrl;
  Task _task = Task(
    id: 0,
    title: '',
    courseName: '',
    status: '',
    isCompleted: false,
  );

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSyncSubmission());
  }

  Future<void> _autoSyncSubmission() async {
    if (_task.url == null) return;

    setState(() => _syncing = true);

    try {
      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return;

      final username = await AuthService.instance.decrypt(cred['encrypted_username'] as String);
      final password = await AuthService.instance.decrypt(cred['encrypted_password'] as String);
      final loginType = cred['login_type'] as String? ?? 'moodle';
      final sessionCookie = loginType == 'office365' ? password : null;

      await MoodleService.instance.checkSubmissionStatus(
        cred['moodle_url'] as String,
        username,
        password,
        _task.url!,
        sessionCookie: sessionCookie,
      );

      final fresh = await DatabaseService.instance.getTask(widget.task.id);
      if (fresh != null && mounted) {
        setState(() => _task = Task.fromJson(fresh));
      }
    } catch (_) {
      // Silent — sync is just a convenience, not required
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _pickAndReplaceFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'zip', 'rar', 'jpg', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _statusMessage = null;
        _uploadSuccess = false;
      });
      await _uploadFile();
    }
  }

  Future<void> _removeSubmission() async {
    setState(() {
      _removing = true;
      _statusMessage = null;
    });

    try {
      final api = context.read<ApiService>();
      final result = await api.removeSubmission(widget.task.id);

      if (!mounted) return;

      setState(() {
        _removing = false;
        _task = Task(
          id: widget.task.id,
          title: widget.task.title,
          courseName: widget.task.courseName,
          dueDate: widget.task.dueDate,
          status: widget.task.status,
          isCompleted: widget.task.isCompleted,
        );
        _uploadSuccess = result['success'] == true;
        _statusMessage = (result['success'] == true
            ? 'Submission removed successfully.'
            : '${result['message'] ?? 'Failed.'} Local data cleared.');
        _selectedFile = null;
      });

      if (result['success'] != true) {
        // Always also update through the provider for consistency
        await api.fetchTasks();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _removing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'zip', 'rar', 'jpg', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _statusMessage = null;
        _uploadSuccess = false;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null || _selectedFile!.path == null) {
      setState(() {
        _statusMessage = 'Please select a file first';
      });
      return;
    }

    setState(() {
      _uploading = true;
      _statusMessage = null;
    });

    try {
      final api = context.read<ApiService>();
      final result = await api.uploadFile(widget.task.id, _selectedFile!.path!);

      final fileUrl = result['file_url'] as String?;
      setState(() {
        _uploadSuccess = result['success'] == true;
        _openInBrowser = result['open_in_browser'] == true;
        _browserUrl = result['url'] ?? widget.task.url;
        _uploadedFileUrl = fileUrl;
        _statusMessage = result['message'] ?? (_uploadSuccess ? 'File uploaded successfully!' : 'Upload failed');
      });

      // Refresh task data so uploaded file shows immediately
      if (_uploadSuccess) {
        final fresh = await DatabaseService.instance.getTask(widget.task.id);
        if (fresh != null && mounted) {
          setState(() => _task = Task.fromJson(fresh));
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Homework'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _task.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _task.courseName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          _task.dueDateFormatted,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_syncing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_task.submissionFiles.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Previously Uploaded Files',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (_task.submissionStatus != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _task.submissionStatus!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ..._task.submissionFiles.map((file) => _buildUploadedFileCard(context, file)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _uploading ? null : () => _pickAndReplaceFile(),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('Replace File'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _removing ? null : _removeSubmission,
                              icon: _removing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete Submission'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select File',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_selectedFile == null)
                      InkWell(
                        onTap: _pickFile,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outline),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.cloud_upload,
                                size: 64,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Tap to select a file',
                                style: theme.textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Supported: PDF, DOC, DOCX, TXT, ZIP, RAR, JPG, PNG',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getFileIcon(_selectedFile!.extension ?? ''),
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedFile!.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatFileSize(_selectedFile!.size),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _selectedFile = null;
                                  _statusMessage = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    if (_selectedFile != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _uploading ? null : _uploadFile,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload),
                          label: Text(_uploading ? 'Uploading...' : 'Upload to Moodle'),
                        ),
                      ),
                    
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _uploadSuccess
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _uploadSuccess ? Colors.green : Colors.orange,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _uploadSuccess ? Icons.check_circle : Icons.info,
                              color: _uploadSuccess ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  color: _uploadSuccess ? Colors.green.shade900 : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_uploadSuccess) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final url = _uploadedFileUrl ?? _browserUrl;
                              if (url != null) {
                                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              }
                              Navigator.pop(context, true);
                            },
                            icon: const Icon(Icons.visibility),
                            label: const Text('View Uploaded File'),
                          ),
                        ),
                      ],
                      if (_openInBrowser && _browserUrl != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse(_browserUrl!), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in Browser'),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadedFileCard(BuildContext context, Map<String, dynamic> file) {
    final theme = Theme.of(context);
    final filename = file['filename'] as String? ?? 'Unknown file';
    final fileType = file['type'] as String? ?? 'file';
    final size = file['size'] as int? ?? 0;
    final uploadedAt = file['uploaded_at'] as String? ?? file['checked_at'] as String?;
    final fileUrl = file['url'] as String?;
    final fileUrlValid = fileUrl != null && fileUrl.isNotEmpty;
    final preview = file['preview'] as String?;

    final isOnlineText = fileType == 'online_text' || filename == 'online_text_submission';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: isOnlineText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.text_fields, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Online Text Submission',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      preview,
                      style: theme.textTheme.bodySmall,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Icon(
                  _getFileIcon(filename.split('.').last),
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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
                if (fileUrlValid)
                  IconButton(
                    icon: Icon(Icons.open_in_new, color: theme.colorScheme.primary, size: 20),
                    tooltip: 'Open file',
                    onPressed: () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
    );
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
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
