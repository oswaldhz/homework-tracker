import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/api_service.dart';

class FileUploadScreen extends StatefulWidget {
  final Task task;

  const FileUploadScreen({super.key, required this.task});

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  PlatformFile? _selectedFile;
  bool _uploading = false;
  String? _statusMessage;
  bool _uploadSuccess = false;
  bool _openInBrowser = false;
  String? _browserUrl;

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

      setState(() {
        _uploadSuccess = result['success'] == true;
        _openInBrowser = result['open_in_browser'] == true;
        _browserUrl = result['url'] ?? widget.task.url;
        _statusMessage = result['message'] ?? (_uploadSuccess ? 'File uploaded successfully!' : 'Upload failed');
      });
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
                      widget.task.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.task.courseName,
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
                          widget.task.dueDateFormatted,
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
                            onPressed: () => Navigator.pop(context, true),
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
