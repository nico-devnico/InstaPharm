/// Compte super-administrateur protégé (non suspendable / non supprimable).
class SuperAdmin {
  SuperAdmin._();

  static const email = 'nicodevnico@gmail.com';

  static bool isSuperAdminEmail(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase() == SuperAdmin.email;
  }

  static bool isProtectedEmail(String? email) => isSuperAdminEmail(email);
}
