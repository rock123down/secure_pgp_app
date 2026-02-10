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

  // Generate a PGP Key Pair (Asymmetric)
  // This is for tge "Public/Private Key" workflow
  static Future<KeyPair> generateKeyPair(String name, String email, String passphrase) async {
    var options = Options()
        ..name = name
        ..email = email
        ..passphrase = passphrase
        ..keyOptions = (KeyOptions()..rsaBits = 2048);

    return await OpenPGP.generate(options: options);
  }
}