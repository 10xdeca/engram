import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/user_profile.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Manages authentication state as a stream.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Signs in with Google. Returns the Firebase [User] or null on cancel.
///
/// Google always provides displayName, email, and photoUrl on every sign-in.
Future<User?> signInWithGoogle(FirebaseAuth auth) async {
  final googleUser = await GoogleSignIn(scopes: ['email', 'profile']).signIn();
  if (googleUser == null) return null; // User cancelled

  final googleAuth = await googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    accessToken: googleAuth.accessToken,
    idToken: googleAuth.idToken,
  );
  final userCredential = await auth.signInWithCredential(credential);
  final user = userCredential.user;
  if (user == null) return null;

  // Write profile to Firestore (idempotent — overwrites with latest data)
  await _writeProfile(
    uid: user.uid,
    displayName: googleUser.displayName ?? user.displayName ?? 'User',
    email: googleUser.email,
    photoUrl: googleUser.photoUrl,
  );
  return user;
}

/// Signs in with Apple. Returns the Firebase [User] or null on failure.
///
/// Apple only provides name + email on the FIRST sign-in. Subsequent
/// sign-ins return null for these fields. We capture and persist immediately.
Future<User?> signInWithApple(FirebaseAuth auth) async {
  final appleCredential = await SignInWithApple.getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.fullName,
      AppleIDAuthorizationScopes.email,
    ],
  );

  final oauthCredential = OAuthProvider('apple.com').credential(
    idToken: appleCredential.identityToken,
    accessToken: appleCredential.authorizationCode,
  );
  final userCredential = await auth.signInWithCredential(oauthCredential);
  final user = userCredential.user;
  if (user == null) return null;

  // Construct display name from Apple's given/family name (first sign-in only)
  final givenName = appleCredential.givenName;
  final familyName = appleCredential.familyName;
  String? appleName;
  if (givenName != null || familyName != null) {
    appleName = [givenName, familyName].whereType<String>().join(' ').trim();
  }

  // Apple never provides a photo URL
  await _writeProfile(
    uid: user.uid,
    displayName: appleName ?? user.displayName ?? 'User',
    email: appleCredential.email ?? user.email,
    photoUrl: null,
    onlyIfNew: appleName == null, // Don't overwrite name if Apple didn't give one
  );
  return user;
}

/// Signs in anonymously. Dev/testing fallback.
Future<String?> ensureSignedIn(FirebaseAuth auth) async {
  if (auth.currentUser != null) {
    return auth.currentUser!.uid;
  }
  final credential = await auth.signInAnonymously();
  return credential.user?.uid;
}

/// Signs out the current user.
Future<void> signOut(FirebaseAuth auth) async {
  await auth.signOut();
}

/// Writes user profile to Firestore.
///
/// If [onlyIfNew] is true, only writes if the profile doc doesn't exist yet.
/// This prevents overwriting Apple name data on subsequent sign-ins where
/// Apple returns null for name fields.
Future<void> _writeProfile({
  required String uid,
  required String displayName,
  String? email,
  String? photoUrl,
  bool onlyIfNew = false,
}) async {
  final docRef =
      FirebaseFirestore.instance.collection('users').doc(uid);
  final profileRef = docRef.collection('profile').doc('main');

  if (onlyIfNew) {
    final existing = await profileRef.get();
    if (existing.exists) return;
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final profile = UserProfile(
    uid: uid,
    displayName: displayName,
    email: email,
    photoUrl: photoUrl,
    currentStreak: 0,
    createdAt: now,
  );
  await profileRef.set(profile.toJson(), SetOptions(merge: true));
}
