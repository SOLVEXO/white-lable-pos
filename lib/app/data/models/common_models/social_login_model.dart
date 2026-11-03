class SocialLoginModel {
  final String authProvider; // 'google', 'facebook', 'apple'
  final String socialId;
  final String userName;
  /// Apple may withhold the email; the backend then uses the verified one inside the identity token.
  final String? email;
  final String? image;
  final String? fcmToken;
  final String? token;

  const SocialLoginModel({
    required this.authProvider,
    required this.socialId,
    required this.userName,
    this.email,
    this.image,
    this.fcmToken,
    this.token,
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
    };
  }
}
