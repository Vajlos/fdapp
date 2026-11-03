import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'home_page.dart';
import 'services/app_language.dart';

// Supabase adresa a anon kľúč: flutter run --dart-define-from-file=supabase.json
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Web OAuth klient z google-services.json (client_type 3). Google token je
// vystavený preň a rovnaké ID musí byť v Supabase pri Google prihlásení.
const _googleWebClientId =
    '706824712336-a7j2qk658kdf6tra6o3ra8f149n3sch6.apps.googleusercontent.com';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'Chýba SUPABASE_URL / SUPABASE_ANON_KEY – spusti appku s '
      '--dart-define-from-file=supabase.json',
    );
  }
  // Firebase ostáva len kvôli AI rozpoznávaniu jedla, prihlásenie je v Supabase.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    // adresa môže byť zadaná aj s "/rest/v1" na konci
    url: _supabaseUrl.replaceFirst(RegExp(r'(/rest/v1)?/*$'), ''),
    publishableKey: _supabaseAnonKey,
  );
  await GoogleSignIn.instance.initialize(serverClientId: _googleWebClientId);
  await AppLanguageController.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const _lilac = Color(0xFFD9B8FF);
  static const _violet = Color(0xFFA66BEE);
  static const _deep = Color(0xFF240747);
  static const _darkBg = Color(0xFF14011F);

  static InputDecorationTheme _inputTheme(Color accent, Color fill) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      labelStyle: TextStyle(color: accent),
      floatingLabelStyle: TextStyle(color: accent),
      border: border(accent.withValues(alpha: 0.5), 1),
      enabledBorder: border(accent.withValues(alpha: 0.5), 1),
      focusedBorder: border(accent, 2),
    );
  }

  static ButtonStyle _buttonStyle() => FilledButton.styleFrom(
    elevation: 6,
    shadowColor: Colors.black87,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );

  @override
  Widget build(BuildContext context) {
    // pri zmene jazyka sa prekreslí celá aplikácia
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageController.instance,
      builder: (context, language, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'Food Diary',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: _lilac,
          onPrimary: _deep,
          surface: Colors.white,
          onSurface: _deep,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: _deep,
          elevation: 0,
        ),
        inputDecorationTheme: _inputTheme(_violet, Colors.white),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _violet,
          selectionHandleColor: _violet,
        ),
        filledButtonTheme: FilledButtonThemeData(style: _buttonStyle()),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _deep),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _darkBg,
        colorScheme: const ColorScheme.dark(
          primary: _deep,
          onPrimary: _lilac,
          surface: _darkBg,
          onSurface: _lilac,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _darkBg,
          foregroundColor: _lilac,
          elevation: 0,
        ),
        inputDecorationTheme: _inputTheme(_lilac, const Color(0xFF1C0430)),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _lilac,
          selectionHandleColor: _lilac,
        ),
        filledButtonTheme: FilledButtonThemeData(style: _buttonStyle()),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _lilac),
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data?.session != null) return const HomePage();
          return const WelcomePage();
        },
      ),
    );
  }
}

/// Úvodná obrazovka: veľké logo a tlačidlá na výber prihlásenia.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) throw 'Google nevrátil ID token';
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } catch (e) {
      setState(() => _error = 'Google prihlásenie zlyhalo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Image.asset('assets/logo.png', height: 240),
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            ),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Prihlásiť účtom'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Prihlásiť Googlom'),
                    ),
                  ),
                  // Sem neskôr pridaj ďalšie tlačidlá (rovnaký vzor
                  // SizedBox(height: 12) + SizedBox s FilledButton.icon).
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prihlásenie / registrácia emailom a heslom.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_isLogin && _password.text != _confirm.text) {
      setState(() => _error = 'Heslá sa nezhodujú');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_isLogin) {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        // Keď je v Supabase zapnuté potvrdenie emailu, session príde až po
        // kliknutí na odkaz v emaile.
        if (res.session == null) {
          setState(() {
            _isLogin = true;
            _error = 'Potvrď registráciu cez odkaz v emaile a potom sa prihlás';
          });
          return;
        }
      }
      // Po úspechu zavri túto obrazovku, aby sa ukázala HomePage.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _shadowed(Widget child) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', height: 100),
                const SizedBox(height: 24),
                _shadowed(
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ),
                const SizedBox(height: 16),
                _shadowed(
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Heslo'),
                  ),
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  _shadowed(
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Heslo znova',
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isLogin ? 'Prihlásiť sa' : 'Zaregistrovať sa'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _isLogin = !_isLogin;
                    _confirm.clear();
                    _error = null;
                  }),
                  child: Text(
                    _isLogin
                        ? 'Nemáš účet? Zaregistruj sa'
                        : 'Už máš účet? Prihlás sa',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
