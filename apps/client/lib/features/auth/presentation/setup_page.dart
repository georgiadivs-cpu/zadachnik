import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../data/auth_api.dart';

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _setupToken = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _setupToken.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _setupToken.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (token.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }
    if (password.length < 12) {
      setState(() => _error = 'Пароль должен содержать не менее 12 символов');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).setup(
            setupToken: token,
            email: email,
            password: password,
          );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() => _error = failure.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Не удалось создать владельца');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Первичная настройка')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Создайте владельца сервера. Нужен setup token из настроек сервера.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('setupToken'),
              controller: _setupToken,
              decoration: const InputDecoration(labelText: 'Setup token'),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('setupEmail'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('setupPassword'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('setupButton'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Создать владельца'),
            ),
            const SizedBox(height: 10),
            Text(
              'Если владелец уже создан, вернитесь и войдите.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
