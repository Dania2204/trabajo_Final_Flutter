import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/database_helper.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';

/// Handles login, registration, and session persistence.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _sessionKey = 'session_user_id';
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // Simple hash — in production use bcrypt/argon2 via a plugin
  String _hash(String password) {
    final bytes = utf8.encode(password + 'paego_salt_2024');
    return base64Encode(bytes);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionKey);
    if (userId != null) {
      _currentUser = await DatabaseHelper.instance.getUserById(userId);
    }
  }

  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String phone,
    required String idNumber,
    required String password,
    required String role,
    String? institution,
    String? photoPath,
  }) async {
    return AuthResult.failure(
      'Self-registration is disabled. Contact an administrator.',
    );
  }

  Future<AuthResult> createUser({
    required AppUser createdBy,
    required String fullName,
    required String email,
    required String phone,
    required String idNumber,
    required String password,
    required String role,
    String? institution,
    String? photoPath,
  }) async {
    if (!createdBy.role.canManageUsers) {
      return AuthResult.failure('Only administrators can create users.');
    }

    try {
      final user = AppUser(
        fullName: fullName,
        email: email.toLowerCase().trim(),
        phone: phone,
        idNumber: idNumber,
        role: UserRoleX.fromString(role),
        institution: institution,
        photoPath: photoPath,
        passwordHash: _hash(password),
        createdAt: DateTime.now(),
        isSynced: false,
      );
      final id = await DatabaseHelper.instance.insertUser(user);
      return AuthResult.success(user.copyWith(id: id));
    } catch (e) {
      if (e.toString().contains('UNIQUE')) {
        return AuthResult.failure('Username/email or ID number already registered.');
      }
      return AuthResult.failure('User creation failed. Please try again.');
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final user = await DatabaseHelper.instance
          .getUserByIdentifier(email.toLowerCase().trim());
      if (user == null) {
        return AuthResult.failure('Invalid username or password.');
      }
      if (user.passwordHash != _hash(password)) {
        return AuthResult.failure('Invalid username or password.');
      }
      _currentUser = user;
      await _persistSession(user.id!);
      return AuthResult.success(user);
    } catch (_) {
      return AuthResult.failure('Login failed. Please try again.');
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<void> _persistSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }
}

class AuthResult {
  AuthResult.success(this.user) : error = null;
  AuthResult.failure(this.error) : user = null;

  final AppUser? user;
  final String? error;

  bool get isSuccess => user != null;
}
