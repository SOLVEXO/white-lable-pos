import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In is the only auth method — same as the buyer app (Facebook/
/// Apple were removed there; this app never had them).
class SocialAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<SocialLoginModel?> signInWithGoogle() async {
    try {
      debugPrint('🔄 Starting Google Sign In...');

      await _googleSignIn.initialize();

      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      final auth = account.authentication;

      return SocialLoginModel(
        authProvider: 'google',
        socialId: account.id,
        userName: account.displayName ?? 'User',
        email: account.email,
        image: account.photoUrl,
        token: auth.idToken,
      );
    } catch (e) {
      debugPrint('❌ Google Sign In error: $e');
      return null;
    }
  }

  Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('✅ Google signed out');
    } catch (e) {
      debugPrint('⚠️ Google sign out error: $e');
    }
  }

  Future<void> signOutAll() async {
    await signOutGoogle();
  }
}
