class PreviewSession {
  PreviewSession._();

  static String _username = 'preview_user';

  static String get username => _username;

  static void signIn(String username) {
    final normalized = username.trim();
    _username = normalized.isEmpty ? 'preview_user' : normalized;
  }

  static void signOut() {
    _username = 'preview_user';
  }
}
