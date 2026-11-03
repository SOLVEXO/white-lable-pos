// 5F.1 — Sign in with Apple: nonce handling and the payload the backend's existing social-login endpoint receives.

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:solvexo_pos/app/data/services/social_auth_service.dart';

void main() {
  test('nonce is random, long enough, URL-safe; Apple gets its SHA-256', () {
    final a = SocialAuthService.generateNonce();
    final b = SocialAuthService.generateNonce();
    expect(a, isNot(b));
    expect(a.length, 32);
    expect(RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(a), isTrue);
    // known SHA-256 vector
    expect(SocialAuthService.sha256Of('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('Apple payload: seller role, identity token, no email key when Apple withholds it', () {
    final json = const SocialLoginModel(authProvider: 'apple', socialId: 'sub-1', userName: 'Apple user', token: 'idtok').toJson();
    expect(json['authProvider'], 'apple');
    expect(json['socialId'], 'sub-1');
    expect(json['token'], 'idtok');
    expect(json['role'], 'seller');
    expect(json.containsKey('email'), isFalse);
  });

  test('Google payload still carries the email', () {
    final json = const SocialLoginModel(authProvider: 'google', socialId: 'g', userName: 'A', email: 'a@b.co', token: 't').toJson();
    expect(json['email'], 'a@b.co');
  });

  test('authorizationCode: sent for Apple, omitted when null/empty, never sent for Google', () {
    final withCode = const SocialLoginModel(authProvider: 'apple', socialId: 's', userName: 'A', token: 't', authorizationCode: 'code-1').toJson();
    expect(withCode['authorizationCode'], 'code-1');
    expect(const SocialLoginModel(authProvider: 'apple', socialId: 's', userName: 'A', token: 't').toJson().containsKey('authorizationCode'), isFalse);
    expect(const SocialLoginModel(authProvider: 'apple', socialId: 's', userName: 'A', token: 't', authorizationCode: '').toJson().containsKey('authorizationCode'), isFalse);
    expect(const SocialLoginModel(authProvider: 'google', socialId: 'g', userName: 'A', token: 't', authorizationCode: 'x').toJson().containsKey('authorizationCode'), isFalse);
  });
}
