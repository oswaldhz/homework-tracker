import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/moodle_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;
  bool _loadingSavedCredentials = true;
  bool _checkingSso = false;
  String? _ssoUrl;
  bool get _ssoDetected => _ssoUrl != null && _ssoUrl!.isNotEmpty;
  
  List<Map<String, dynamic>> _savedCredentials = [];
  String? _selectedCredentialId;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      var savedUrl = _urlController.text;
      var savedUsername = _usernameController.text;
      var savedPassword = _passwordController.text;
      var rememberMe = false;
      List<Map<String, dynamic>> savedCredentials = [];

      // First: try the database (persists across sessions)
      // SharedPreferences does NOT persist on Windows (file ends up as {}),
      // so we must use the DB as the primary source for credentials.
      try {
        final api = context.read<ApiService>();

        // Try remember_me=1 first
        savedCredentials = await api.getAllSavedCredentials();
        await Logger.instance.log('LOAD_CRED: DB getAllSavedCredentials returned ${savedCredentials.length}');

        if (savedCredentials.isEmpty) {
          // Fallback: any credential regardless of remember_me flag
          final anyCred = await api.getAnyCredential();
          if (anyCred != null) {
            savedCredentials = [anyCred];
            rememberMe = (anyCred['remember_me'] as int? ?? 0) == 1;
            await Logger.instance.log('LOAD_CRED: DB getAnyCredential found one, remember_me=$rememberMe');
          } else {
            await Logger.instance.log('LOAD_CRED: DB has no credentials at all');
          }
        } else {
          rememberMe = true;
        }

        if (savedCredentials.isNotEmpty) {
          final cred = savedCredentials.first;
          final dbUrl = cred['moodle_url'] as String? ?? '';
          final dbUsername = await api.decryptUsername(cred['encrypted_username'] as String);
          final dbPassword = await api.decryptPassword(cred['encrypted_password'] as String);
          final dbLoginType = cred['login_type'] as String? ?? 'moodle';

          _urlController.text = dbUrl;
          _usernameController.text = dbUsername;
          if (dbLoginType != 'office365') {
            _passwordController.text = dbPassword;
          }
          savedUrl = dbUrl;
          savedUsername = dbUsername;
          savedPassword = dbPassword;
        }

        await Logger.instance.log('LOAD_CRED: after DB - savedUrl=$savedUrl, '
            'savedUsername=$savedUsername, savedPasswordLen=${savedPassword.length}'
            ', rememberMe=$rememberMe');
      } catch (dbErr) {
        await Logger.instance.log('LOAD_CRED: DB error: $dbErr');
      }

      // Second: also read from SharedPreferences as a fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        final sfUrl = prefs.getString('moodle_url');
        final sfUsername = prefs.getString('username');
        final sfPassword = prefs.getString('password');
        final sfLoginType = prefs.getString('login_type') ?? 'moodle';
        final sfRememberMe = prefs.getBool('remember_me') ?? false;

        await Logger.instance.log('LOAD_CRED: SharedPreferences - url=$sfUrl, user=$sfUsername, '
            'password=${sfPassword != null ? 'set(${sfPassword.length})' : 'null'}'
            ', rememberMe=$sfRememberMe');

        // Only use SharedPreferences data if DB didn't provide any
        if (savedCredentials.isEmpty) {
          if (sfUrl != null) _urlController.text = sfUrl;
          if (sfUsername != null) _usernameController.text = sfUsername;
          if (sfLoginType != 'office365' && sfPassword != null) {
            _passwordController.text = sfPassword;
          }
          rememberMe = sfRememberMe;
          savedUrl = sfUrl ?? '';
          savedUsername = sfUsername ?? '';
          savedPassword = sfPassword ?? '';
        }
      } catch (prefsErr) {
        await Logger.instance.log('LOAD_CRED: SharedPreferences error: $prefsErr');
      }

      bool shouldAutoLogin = false;
      setState(() {
        _savedCredentials = savedCredentials;
        _rememberMe = rememberMe;
        _loadingSavedCredentials = false;
        if (rememberMe && savedUrl.isNotEmpty && savedUsername.isNotEmpty && savedPassword.isNotEmpty) {
          shouldAutoLogin = true;
        }
      });

      if (shouldAutoLogin) {
        await Logger.instance.log('LOAD_CRED: shouldAutoLogin=true, navigating to dashboard');
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          await _handleLogin();
          return;
        }
      }

      final checkUrl = savedUrl.isNotEmpty ? savedUrl : (savedCredentials.isNotEmpty ? savedCredentials.first['moodle_url'] as String? : null);
      if (checkUrl != null && checkUrl.isNotEmpty) {
        await _detectSso(checkUrl);
      }
    } catch (e) {
      await Logger.instance.log('LOAD_CRED: critical error: $e');
      setState(() {
        _loadingSavedCredentials = false;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (!_rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('moodle_url');
      await prefs.remove('username');
      await prefs.remove('password');
      await prefs.remove('login_type');
      await prefs.remove('session_cookie');
      await prefs.setBool('remember_me', false);
      await Logger.instance.log('SAVE_CRED: cleared (rememberMe=false)');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('moodle_url', _urlController.text.trim());
    await prefs.setString('username', _usernameController.text.trim());
    await prefs.setString('password', _passwordController.text);
    await prefs.setBool('remember_me', true);
    await Logger.instance.log('SAVE_CRED: saved to prefs (url=${_urlController.text.trim()}, user=${_usernameController.text.trim()}, passwordLen=${_passwordController.text.length})');
    
    // Also save to database for autocomplete
    final api = context.read<ApiService>();
    await api.saveCredentials(
      _urlController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text,
      rememberMe: true,
    );
    await Logger.instance.log('SAVE_CRED: saved to DB');
  }

  Future<void> _detectSso(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return;

    setState(() {
      _checkingSso = true;
    });

    try {
      final sso = await MoodleService.instance.detectSsoLogin(url);
      if (mounted) {
        setState(() {
          _ssoUrl = sso;
          _checkingSso = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ssoUrl = null;
          _checkingSso = false;
        });
      }
    }
  }

  Future<void> _selectSavedCredential(Map<String, dynamic> cred) async {
    final api = context.read<ApiService>();
    final username = await api.decryptUsername(cred['encrypted_username']);
    final password = await api.decryptPassword(cred['encrypted_password']);
    
    setState(() {
      _urlController.text = cred['moodle_url'] as String;
      _usernameController.text = username;
      _passwordController.text = password;
      _rememberMe = (cred['remember_me'] as int? ?? 0) == 1;
      _selectedCredentialId = cred['id'].toString();
    });
    
    await _detectSso(cred['moodle_url'] as String);
  }

  Future<void> _deleteSavedCredential(int id) async {
    final api = context.read<ApiService>();
    await api.deleteSavedCredential(id);
    final updated = await api.getAllSavedCredentials();
    setState(() {
      _savedCredentials = updated;
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final api = context.read<ApiService>();
    final result = await api.login(
      _urlController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (result['success'] == true) {
      await _saveCredentials();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } else if (mounted) {
      final message = result['message'] ?? 'Login failed. Check your credentials and Moodle URL.';
      final errorLower = message.toLowerCase();
      final isSessionError = errorLower.contains('sesion') ||
          errorLower.contains('session') ||
          errorLower.contains('timeout') ||
          errorLower.contains('time limit');

      setState(() {
        if (isSessionError && _ssoDetected) {
          _error = '$message\n\nThis Moodle site uses Office 365 login. Please use the "Login with Office 365" button below.';
        } else {
          _error = message;
        }
      });
      // Check for SSO option after a normal login failure
      await _detectSso(_urlController.text.trim());
    }
  }

  Future<void> _handleOffice365Login() async {
    if (_ssoUrl == null || _ssoUrl!.isEmpty) return;

    final api = context.read<ApiService>();
    final cookie = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _Office365CookieDialog(ssoUrl: _ssoUrl!),
    );

    if (cookie == null || cookie.trim().isEmpty) return;
    if (!mounted) return;

    final result = await api.login(
      _urlController.text.trim(),
      _usernameController.text.trim().isEmpty ? 'office365_user' : _usernameController.text.trim(),
      '',
      loginType: 'office365',
      sessionCookie: cookie.trim(),
    );

    if (result['success'] == true) {
      await _saveCredentials();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } else if (mounted) {
      setState(() {
        _error = result['message'] ?? 'Office 365 login failed. Please check the cookie and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();

    if (_loadingSavedCredentials) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.school_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Homework Tracker',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect your Moodle account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_savedCredentials.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_circle,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saved Accounts',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedCredentialId,
                            decoration: InputDecoration(
                              labelText: 'Select account to login',
                              hintText: 'Choose a saved account',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              suffixIcon: _selectedCredentialId != null
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () {
                                        final id = int.tryParse(_selectedCredentialId!);
                                        if (id != null) _deleteSavedCredential(id);
                                        setState(() {
                                          _selectedCredentialId = null;
                                          _urlController.clear();
                                          _usernameController.clear();
                                          _passwordController.clear();
                                        });
                                      },
                                      tooltip: 'Forget this account',
                                    )
                                  : null,
                            ),
                            items: _savedCredentials.map((cred) {
                              final url = cred['moodle_url'] as String;
                              final username = cred['encrypted_username'] as String;
                              return DropdownMenuItem<String>(
                                value: cred['id'].toString(),
                                child: Text(
                                  '$username @ $url',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              final cred = _savedCredentials.firstWhere((c) => c['id'].toString() == value);
                              _selectSavedCredential(cred);
                            },
                          ),
                          if (_selectedCredentialId != null) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: api.loading ? null : _handleLogin,
                              icon: api.loading
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.login),
                              label: Text(api.loading ? 'Connecting...' : 'Quick Login'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or enter new credentials',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_ssoDetected) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Office 365 login detected. If your normal credentials don\'t work, use the Office 365 button below.',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _urlController,
                    onChanged: (value) {
                      if (_ssoDetected) {
                        setState(() => _ssoUrl = null);
                      }
                    },
                    onFieldSubmitted: (value) => _detectSso(value.trim()),
                    onTapOutside: (_) => _detectSso(_urlController.text.trim()),
                    decoration: InputDecoration(
                      labelText: 'Moodle URL',
                      hintText: 'https://your-school.moodle.com',
                      prefixIcon: const Icon(Icons.link),
                      border: const OutlineInputBorder(),
                      helperText: 'Your school\'s Moodle website address',
                      suffixIcon: _checkingSso
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: Padding(
                                padding: EdgeInsets.all(10.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _ssoDetected
                              ? const Tooltip(
                                  message: 'Office 365 login detected',
                                  child: Icon(Icons.cloud, color: Colors.blue),
                                )
                              : null,
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Enter your Moodle URL';
                      if (!value.startsWith('http')) return 'URL must start with http:// or https://';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'Your Moodle username',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Enter your username';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Your Moodle password',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Enter your password';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Remember me',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Save credentials for quick login next time',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: api.loading ? null : _handleLogin,
                    icon: api.loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: Text(api.loading ? 'Connecting...' : 'Connect'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  if (_ssoDetected) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('OR'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: api.loading ? null : _handleOffice365Login,
                      icon: const Icon(Icons.cloud),
                      label: const Text('Login with Office 365'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Office365CookieDialog extends StatefulWidget {
  final String ssoUrl;

  const _Office365CookieDialog({required this.ssoUrl});

  @override
  State<_Office365CookieDialog> createState() => _Office365CookieDialogState();
}

class _Office365CookieDialogState extends State<_Office365CookieDialog> {
  final _cookieController = TextEditingController();
  bool _obscureCookie = true;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _openSsoInBrowser() async {
    final uri = Uri.parse(widget.ssoUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the browser')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Office 365 Login'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We will open your browser to log in through Office 365. After you are logged in, come back here and paste your Moodle session cookie.',
            ),
            const SizedBox(height: 16),
            const Text(
              'How to find the cookie:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Click "Open Browser" below and log in.\n'
              '2. Press F12 → Application / Storage → Cookies.\n'
              '3. Find "MoodleSession" and copy its Value.\n'
              '4. Paste it here and tap Connect.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cookieController,
              obscureText: _obscureCookie,
              decoration: InputDecoration(
                labelText: 'MoodleSession cookie',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCookie ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureCookie = !_obscureCookie),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _openSsoInBrowser,
          child: const Text('Open Browser'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_cookieController.text.trim()),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
