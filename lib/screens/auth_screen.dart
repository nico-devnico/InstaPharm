import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../services/auth_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String _role = 'patient';

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _businessName = TextEditingController();
  final _businessAddress = TextEditingController();
  final _businessCity = TextEditingController();
  final _license = TextEditingController();
  final _notes = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _businessName.dispose();
    _businessAddress.dispose();
    _businessCity.dispose();
    _license.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await AuthService.instance.signIn(
          email: _email.text,
          password: _password.text,
        );
      } else {
        final res = await AuthService.instance.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          phone: _phone.text,
          role: _role,
          businessName: _businessName.text,
          businessAddress: _businessAddress.text,
          businessCity: _businessCity.text,
          licenseNumber: _license.text,
          applicationNotes: _notes.text,
        );
        if (!mounted) return;
        final pendingPro = _role == 'pharmacist' || _role == 'courier';
        if (res.session == null || pendingPro) {
          setState(() {
            _isLogin = true;
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                pendingPro
                    ? 'Demande enregistrée. Un administrateur doit approuver '
                        'votre compte ${_role == 'pharmacist' ? 'pharmacien' : 'livreur'} '
                        'après vérification des documents.'
                    : 'Compte créé. Vérifiez votre email puis connectez-vous.',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    final maxW = Responsive.isWide(context) ? 420.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isNarrow ? 20 : 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'InstaPharm',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isNarrow ? 28 : 32,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin
                          ? 'Connectez-vous pour commander et suivre vos livraisons'
                          : (_role == 'patient'
                              ? 'Créez un compte patient'
                              : 'Inscription pro — validation admin requise'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isNarrow ? 13 : 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nom complet',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 2)
                                ? 'Nom requis'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone (+237)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(
                          labelText: 'Je suis',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'patient',
                            child: Text('Patient'),
                          ),
                          DropdownMenuItem(
                            value: 'pharmacist',
                            child: Text('Pharmacien (à valider)'),
                          ),
                          DropdownMenuItem(
                            value: 'courier',
                            child: Text('Livreur (à valider)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _role = v);
                        },
                      ),
                      if (_role == 'pharmacist' || _role == 'courier') ...[
                        const SizedBox(height: 12),
                        Text(
                          'Documents / infos pour validation admin',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isNarrow ? 13 : 14,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_role == 'pharmacist') ...[
                          TextFormField(
                            controller: _businessName,
                            decoration: const InputDecoration(
                              labelText: 'Nom de la pharmacie *',
                              prefixIcon: Icon(Icons.local_pharmacy_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _businessCity,
                            decoration: const InputDecoration(
                              labelText: 'Ville *',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _businessAddress,
                            decoration: const InputDecoration(
                              labelText: 'Adresse *',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _license,
                            decoration: const InputDecoration(
                              labelText: 'N° autorisation / licence *',
                              helperText:
                                  'Réf. document officiel (ordre / ministère)',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                        ],
                        if (_role == 'courier') ...[
                          TextFormField(
                            controller: _license,
                            decoration: const InputDecoration(
                              labelText: 'N° pièce d’identité *',
                              helperText: 'CNI / passeport / permis',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Infos complémentaires',
                            hintText:
                                'Lien Drive/WhatsApp des scans de documents, zone, etc.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sans validation admin, le compte reste patient. '
                          'Après inscription, ouvrez Profil pour déposer '
                          'votre pièce d’identité et le justificatif (image/PDF).',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || !v.contains('@')) {
                          return 'Email invalide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6)
                              ? '6 caractères minimum'
                              : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isLogin ? 'Se connecter' : 'Créer mon compte'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _isLogin = !_isLogin;
                                _error = null;
                              }),
                      child: Text(
                        _isLogin
                            ? 'Pas de compte ? S’inscrire'
                            : 'Déjà un compte ? Se connecter',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
