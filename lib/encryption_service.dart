import 'package:openpgp/openpgp.dart';

class EncryptionService {
  static Future<String> encryptSymmetric(String text, String password) async {
    try {
      return await OpenPGP.encryptSymmetric(text, password);
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

      return await OpenPGP.decryptSymmetric(cleanInput, password);
    } catch (e) {
      print("PGP Engine Error: $e");
      return "Decryption failed. Check password or data integrity";
    }
  }

  // Inside encryption_service.dart

  static Future<String> encryptAsymmetric(String text, String publicKey) async {
    try {
      return await OpenPGP.encrypt(text, publicKey);
    } catch (e) {
      return "Error: $e";
    }
  }

  static Future<String> decryptAsymmetric(String encryptedText, String privateKey, String passphrase) async {
    try {
      return await OpenPGP.decrypt(encryptedText, privateKey, passphrase);
    } catch (e) {
      return "Decryption Error: Check passphrase";
    }
  }

  // Updated for openpgp 3.x.x API
  static Future<Options> _buildOptions(String name, String email, String password) async {
    return Options()
      ..passphrase = password
      ..keyOptions = (KeyOptions()
        ..rsaBits = 2048
        ..algorithm = Algorithm.RSA
        ..cipher = Cipher.AES256
        ..compression = Compression.ZLIB
        ..hash = Hash.SHA256);
  }

  // Generate a PGP Key Pair (Asymmetric)
  static Future<KeyPair> generateKeyPair(String name, String email, String password) async {
    try {
      final options = await _buildOptions(name, email, password);
      // In 3.x.x, the 'generate' method expects the 'Options' class
      return await OpenPGP.generate(options: options);
    } catch (e) {
      print("Generation Error: $e");
      rethrow;
    }
  }
}