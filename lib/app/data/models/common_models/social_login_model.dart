class SocialLoginModel {
  final String authProvider; // 'google', 'facebook', 'apple'
  final String socialId;
  final String userName;
  /// Apple may withhold the email; the backend then uses the verified one inside the identity token.
  final String? email;
  final String? image;
  final String? fcmToken;
  final String? token;
  /// Apple only: one-time authorization code the backend exchanges server-side for a revocable refresh token. Never logged.
  final String? authorizationCode;

  const SocialLoginModel({
    required this.authProvider,
    required this.socialId,
    required this.userName,
    this.email,
    this.image,
    this.fcmToken,
    this.token,
    this.authorizationCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'authProvider': authProvider,
      'socialId': socialId,
      'userName': userName,
      if (email != null && email!.isNotEmpty) 'email': email,
      'role': 'seller',
      if (image != null) 'image': image,
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (token != null) 'token': token,
      if (authProvider == 'apple' && authorizationCode != null && authorizationCode!.isNotEmpty) 'authorizationCode': authorizationCode,
    };
  }
}
