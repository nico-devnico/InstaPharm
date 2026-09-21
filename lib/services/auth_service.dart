import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _db => SupabaseService.client;

  User? get currentUser => _db.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => _db.auth.onAuthStateChange;

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw Exception('Non connecté');
    }
    // Vérifie l'ancien mot de passe
    await _db.auth.signInWithPassword(email: email, password: currentPassword);
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String role = 'patient',
    String? businessName,
    String? businessAddress,
    String? businessCity,
    String? licenseNumber,
    String? applicationNotes,
  }) async {
    // Pharmacien / livreur : rôle effectif = patient jusqu'à approbation admin
    return _db.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
        if (businessName != null && businessName.isNotEmpty)
          'business_name': businessName.trim(),
        if (businessAddress != null && businessAddress.isNotEmpty)
          'business_address': businessAddress.trim(),
        if (businessCity != null && businessCity.isNotEmpty)
          'business_city': businessCity.trim(),
        if (licenseNumber != null && licenseNumber.isNotEmpty)
          'license_number': licenseNumber.trim(),
        if (applicationNotes != null && applicationNotes.isNotEmpty)
          'application_notes': applicationNotes.trim(),
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _db.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    // Refuse immédiatement un compte suspendu
    final uid = res.user?.id ?? _db.auth.currentUser?.id;
    if (uid != null) {
      final row = await _db
          .from('profiles')
          .select('is_active, disabled_reason')
          .eq('id', uid)
          .maybeSingle();
      if (row != null && row['is_active'] == false) {
        await signOut();
        throw Exception(
          row['disabled_reason']?.toString().isNotEmpty == true
              ? row['disabled_reason'].toString()
              : 'Compte suspendu. Contactez le support InstaPharm.',
        );
      }
    }
    return res;
  }

  Future<void> signOut() => _db.auth.signOut();

  Future<AppUser?> fetchProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) {
      return AppUser(
        id: uid,
        email: currentUser!.email,
        fullName: currentUser!.userMetadata?['full_name'] as String?,
        phone: currentUser!.userMetadata?['phone'] as String?,
      );
    }
    return AppUser.fromJson(row);
  }

  Future<void> deleteMyAccount() async {
    final rpc = await _db.rpc('delete_my_account');
    if (rpc is Map && rpc['ok'] == false) {
      throw Exception(
        rpc['message']?.toString() ??
            rpc['error']?.toString() ??
            'Suppression refusée',
      );
    }
    await signOut();
  }

  Future<void> updateProfile({
    String? fullName,
    String? phone,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Non connecté');
    await _db.from('profiles').update({
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);
  }
}
