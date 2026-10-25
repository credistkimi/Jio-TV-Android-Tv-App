class AuthState {
  final bool isAuthenticated;
  final String? ssoToken;
  final String? mobileNumber;
  final String? deviceCode;
  final String? qrPayload;
  final DateTime? expiresAt;
  final bool isGuest;

  const AuthState({
    required this.isAuthenticated,
    this.ssoToken,
    this.mobileNumber,
    this.deviceCode,
    this.qrPayload,
    this.expiresAt,
    this.isGuest = false,
  });

  factory AuthState.unauthenticated() {
    return const AuthState(isAuthenticated: false);
  }

  factory AuthState.guest() {
    return const AuthState(isAuthenticated: true, isGuest: true, mobileNumber: 'Guest Mode');
  }

  factory AuthState.authenticated({
    required String ssoToken,
    required String mobileNumber,
  }) {
    return AuthState(
      isAuthenticated: true,
      ssoToken: ssoToken,
      mobileNumber: mobileNumber,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
  }

  AuthState copyWith({
    bool? isAuthenticated,
    String? ssoToken,
    String? mobileNumber,
    String? deviceCode,
    String? qrPayload,
    DateTime? expiresAt,
    bool? isGuest,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      ssoToken: ssoToken ?? this.ssoToken,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      deviceCode: deviceCode ?? this.deviceCode,
      qrPayload: qrPayload ?? this.qrPayload,
      expiresAt: expiresAt ?? this.expiresAt,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
