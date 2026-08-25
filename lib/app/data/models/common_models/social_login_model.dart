class SocialLoginModel {
  final String authProvider; // 'google', 'facebook', 'apple'
  final String socialId;
  final String userName;
  final String email;
  final String? image;
  final String? fcmToken;
  final String? token;

  SocialLoginModel({
    required this.authProvider,
    required this.socialId,
    required this.userName,
    required this.email,
    this.image,
    this.fcmToken,
    this.token,
  });

  Map<String, dynamic> toJson() {
    return {
      'authProvider': authProvider,
      'socialId': socialId,
      'userName': userName,
      'email': email,
      if (image != null) 'image': image,
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (token != null) 'token': token,
    };
  }
}
