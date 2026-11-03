import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Owner social sign-in: Google (both platforms) and Sign in with Apple (iOS only). Apple requires the latter whenever a
/// third-party login is offered (App Store guideline 4.8). The same two calls are used to RE-AUTHENTICATE for account
/// deletion (see DeleteAccountView) — they return a fresh provider identity token the backend verifies itself.
class SocialAuthService {
  /// Apple button is shown on iOS only; Android keeps Google (Apple's web flow would need a Services ID redirect — not offered).
  static bool get appleSupported => Platform.isIOS;

  /// Random nonce; Apple gets its SHA-256, the identity token then carries that hash so a stolen token can't be replayed.
  static String generateNonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String sha256Of(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Returns null when the user cancels; throws on a real failure (the controller shows one plain message).
  Future<SocialLoginModel?> signInWithApple() async {
    final rawNonce = generateNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: sha256Of(rawNonce),
      );
      final token = credential.identityToken;
      final id = credential.userIdentifier;
      if (token == null || id == null) throw StateError('Apple returned no identity token');
      // Name/email are only supplied on the FIRST authorisation; the backend reads the verified email from the token itself.
      final name = [credential.givenName, credential.familyName].whereType<String>().where((e) => e.isNotEmpty).join(' ');
      return SocialLoginModel(
        authProvider: 'apple',
        socialId: id,
        userName: name.isEmpty ? 'Apple user' : name,
        email: credential.email,
        token: token,
        authorizationCode: credential.authorizationCode,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<SocialLoginModel?> signInWithGoogle() async {
    try {
      debugPrint('🔄 Starting Google Sign In...');

      // Web OAuth client id matching the backend's GOOGLE_CLIENT_ID env var,
      // needed so GoogleSignInAccount.authentication returns an idToken whose
      // audience the server accepts.
      await _googleSignIn.initialize(
        serverClientId: '707145385701-quuhmj7p5tgvr1jjuuqgb0h0t2r7rqk2.apps.googleusercontent.com',
      );

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
