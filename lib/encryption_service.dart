import 'package:openpgp/openpgp.dart';

class EncryptionService {
  static const String _noPass = "unlocked_vault_2026";

  static Future<String> encryptSymmetric(String text, String password) async {
    try {
      final effectivePassword = password.isEmpty ? _noPass : password;
      return await OpenPGP.encryptSymmetric(text, effectivePassword);
    } catch (e) {
      return "Encryption Failed: $e";
    }
  }

  static Future<String> decryptSymmetric(String encryptedText, String password) async {
    try {
      String cleanInput = encryptedText.trim();
      if (!cleanInput.contains("-----BEGIN PGP MESSAGE-----")) {
        return "Error: This does not look like a PGP message";
      }
      final effectivePassword = password.isEmpty ? _noPass : password;
      return await OpenPGP.decryptSymmetric(cleanInput, effectivePassword);
    } catch (e) {
      return "Decryption failed. Check password or data integrity";
    }
  }

  static Future<String> encryptAsymmetric(String text, String publicKey) async {
    try {
      // 2 arguments only: No private key means NO signature and NO popup.
      return await OpenPGP.encrypt(text, publicKey);
    } catch (e) {
      return "Encryption Error: $e";
    }
  }

  static Future<String> decryptAsymmetric(String encryptedText, String privateKey, String passphrase) async {
    try {
      // Since we now enforce passwords at generation, passphrase should never be empty.
      return await OpenPGP.decrypt(encryptedText, privateKey, passphrase);
    } catch (e) {
      return "Decryption Error: Check passphrase";
    }
  }

  static Future<KeyPair> generateKeyPair(String name, String email, String password) async {
    if (password.isEmpty) {
      throw Exception("Password is required to secure your private key.");
    }

    try {
      final options = Options()
        ..name = name
        ..email = email
        ..passphrase = password // Mandatory password
        ..keyOptions = (KeyOptions()
          ..rsaBits = 2048
          ..algorithm = Algorithm.RSA);

      return await OpenPGP.generate(options: options);
    } catch (e) {
      rethrow;
    }
  }
}