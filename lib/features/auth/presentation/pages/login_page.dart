import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../providers/sesion_notifier.dart';

/// Pantalla de inicio de sesión (esqueleto — HU-AUTH-003 la completa en Sprint 3).
///
/// Sin lógica de negocio: valida por [Failure] que devuelve el notifier y muestra los mensajes
/// por campo o un banner general.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  Map<String, String> _erroresCampo = const {};
  String? _errorGeneral;
  bool _enviando = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erroresCampo = const {};
      _errorGeneral = null;
    });

    final failure = await ref
        .read(sesionProvider.notifier)
        .iniciarSesion(email: _email.text, password: _password.text);

    if (!mounted) return;
    setState(() {
      _enviando = false;
      switch (failure) {
        case null:
          break;
        case FailureValidacion(:final campos):
          _erroresCampo = campos;
        case Failure(:final mensaje):
          _errorGeneral = mensaje;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('login_email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      errorText: _erroresCampo['email'],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('login_password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _enviando ? null : _enviar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      errorText: _erroresCampo['password'],
                    ),
                  ),
                  if (_errorGeneral != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorGeneral!,
                      key: const Key('login_error_general'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('login_enviar'),
                    onPressed: _enviando ? null : _enviar,
                    child: _enviando
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
