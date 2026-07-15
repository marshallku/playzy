/// A signed-in session: the opaque backend session [token] and the [accountId] it
/// authenticates. The token is never parsed on the client — the account id is
/// stored alongside it (WU5).
class AuthSession {
  const AuthSession({required this.token, required this.accountId});

  final String token;
  final String accountId;

  Map<String, dynamic> toJson() => {'token': token, 'accountId': accountId};

  /// Rebuilds a session from a stored record, returning null when the record is
  /// partial or malformed (either field missing/blank) — a broken record is
  /// treated as "no session" rather than a half-authenticated state.
  static AuthSession? fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final accountId = json['accountId'];
    if (token is String && token.isNotEmpty && accountId is String && accountId.isNotEmpty) {
      return AuthSession(token: token, accountId: accountId);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.token == token && other.accountId == accountId;

  @override
  int get hashCode => Object.hash(token, accountId);
}
