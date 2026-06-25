import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/api_service.dart';

class QuizScreen extends StatefulWidget {
  final Task task;

  const QuizScreen({super.key, required this.task});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Map<String, dynamic>> _questions = [];
  Map<String, dynamic> _answers = {};
  bool _loading = true;
  bool _submitting = false;
  String? _statusMessage;
  bool _submitSuccess = false;
  bool _openInBrowser = false;
  String? _browserUrl;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final api = context.read<ApiService>();
      final data = await api.getQuiz(widget.task.id);

      if (data['success'] == true) {
        setState(() {
          _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _statusMessage = data['message'] ?? 'Failed to load quiz';
          _openInBrowser = data['open_in_browser'] == true;
          _browserUrl = data['url'] ?? widget.task.url;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _submitQuiz() async {
    setState(() {
      _submitting = true;
      _statusMessage = null;
    });

    try {
      final api = context.read<ApiService>();
      final stringAnswers = _answers.map((key, value) => MapEntry(key.toString(), value.toString()));
      final result = await api.submitQuiz(widget.task.id, stringAnswers);

      setState(() {
        _submitSuccess = result['success'] == true;
        _openInBrowser = result['open_in_browser'] == true;
        _browserUrl = result['url'] ?? widget.task.url;
        _statusMessage = result['message'] ?? (_submitSuccess ? 'Quiz submitted successfully!' : 'Submission failed');
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _statusMessage != null && _questions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage!,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_openInBrowser && _browserUrl != null)
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse(_browserUrl!), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in Browser'),
                          ),
                        if (!_openInBrowser) ...[
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadQuiz,
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
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
                                '${_questions.length} questions',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      ..._questions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final question = entry.value;
                        return _buildQuestionCard(index, question);
                      }),
                      
                      const SizedBox(height: 16),
                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submitQuiz,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(_submitting ? 'Submitting...' : 'Submit Quiz'),
                        ),
                      ),
                      
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _submitSuccess
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _submitSuccess ? Colors.green : Colors.orange,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _submitSuccess ? Icons.check_circle : Icons.info,
                                color: _submitSuccess ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: TextStyle(
                                    color: _submitSuccess ? Colors.green.shade900 : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_openInBrowser && _browserUrl != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse(_browserUrl!), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in Browser'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildQuestionCard(int index, Map<String, dynamic> question) {
    final theme = Theme.of(context);
    final questionText = question['text'] ?? '';
    final questionType = question['type'] ?? 'unknown';
    final answers = List<Map<String, dynamic>>.from(question['answers'] ?? []);
    final questionId = question['id'].toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    questionText,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (questionType == 'multiple_choice')
              ...answers.map((answer) {
                final answerText = answer['text'] ?? '';
                final answerValue = answer['value'] ?? '';
                final isSelected = _answers[questionId] == answerValue;
                
                return RadioListTile<String>(
                  title: Text(answerText),
                  value: answerValue,
                  groupValue: _answers[questionId],
                  onChanged: (value) {
                    setState(() {
                      _answers[questionId] = value;
                    });
                  },
                  selected: isSelected,
                );
              }),
            
            if (questionType == 'checkbox')
              ...answers.map((answer) {
                final answerText = answer['text'] ?? '';
                final answerValue = answer['value'] ?? '';
                final selectedValues = List<String>.from(_answers[questionId] ?? []);
                final isSelected = selectedValues.contains(answerValue);
                
                return CheckboxListTile(
                  title: Text(answerText),
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        selectedValues.add(answerValue);
                      } else {
                        selectedValues.remove(answerValue);
                      }
                      _answers[questionId] = selectedValues;
                    });
                  },
                );
              }),
            
            if (questionType == 'text')
              TextField(
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type your answer here...',
                ),
                onChanged: (value) {
                  _answers[questionId] = value;
                },
              ),
            
            if (questionType == 'unknown')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This question type is not supported yet. Please answer it on Moodle.',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
