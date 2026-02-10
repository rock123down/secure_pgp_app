import 'package:flutter/material.dart';
import 'encryption_service.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const EncryptionApp());
}

class EncryptionApp extends StatelessWidget {
  const EncryptionApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Cleaner UI
      title: 'Secure PGP Vault',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        )
      ),
      home: const EncryptionHome(),
    );
  }
}

class EncryptionHome extends StatefulWidget {
  const EncryptionHome({super.key});
  @override
  State<EncryptionHome> createState() => _EncryptionHomeState();
}

class _EncryptionHomeState extends State<EncryptionHome> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _result = "";
  String _statusMessage = "";

  void _handleEncrypt() async {
    // 1. Check if password is empty
    if (_passwordController.text.isEmpty) {
      setState(() => _statusMessage = "Error: Please enter a password to encrypt.");
      return;
    }

    // 2. Clear status and encrypt
    setState(() => _statusMessage = "Encrypting...");
    final encrypted = await EncryptionService.encryptSymmetric(
        _textController.text, _passwordController.text);

    setState(() {
      _result = encrypted;
      _statusMessage = "Encrypted successfully!";
    });
  }

  void _handleDecrypt() async {
    // 1. Pre-flight checks
    if (!_result.contains("-----BEGIN PGP MESSAGE-----")) {
      setState(() => _statusMessage = "Error: No PGP message found to decrypt!");
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() => _statusMessage = "Error: Password is required for decryption.");
      return;
    }

    setState(() => _statusMessage = "Decrypting...");

    // 2. Attempt Decryption
    final decrypted = await EncryptionService.decryptSymmetric(
        _result, _passwordController.text);

    setState(() {
      if (decrypted.contains("Decryption failed")) {
        _statusMessage = "Incorrect password. Please try again.";
      } else {
        _result = decrypted;
        _statusMessage = "Decryption Successful!";
      }
    });
  }

  void _copyToClipboard() {
    if (_result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _result));

      // Show a quick confirmation at the bottom of the screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Copied to clipboard!"),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the theme colors to keep things consistent
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("🔐 Secure PGP Vault"),
        centerTitle: true,
        elevation: 2,
      ),
      body: Center(
        child: ConstrainedBox(
          // On Desktop/Ubuntu, this prevents the UI from stretching too wide
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  maxLines: 5, // Better for long messages
                  decoration: const InputDecoration(
                    labelText: "Message / PGP Block",
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Encryption Password",
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),

                // Status Message Area
                if (_statusMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _statusMessage.contains("Error")
                          ? Colors.redAccent.withOpacity(0.1)
                          : Colors.greenAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _statusMessage.contains("Error")
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleEncrypt,
                        icon: const Icon(Icons.security),
                        label: const Text("Encrypt"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleDecrypt,
                        icon: const Icon(Icons.no_encryption_gmailerrorred),
                        label: const Text("Decrypt"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "RESULT",
                      style: TextStyle(
                        letterSpacing: 1.5,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    if (_result.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy_all, size: 20),
                        tooltip: "Copy to Clipboard",
                        color: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outline.withOpacity(0.5)),
                  ),
                  constraints: const BoxConstraints(minHeight: 150, maxHeight: 300),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _result,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ),
                // Clear Button
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _textController.clear();
                      _passwordController.clear();
                      _result = "";
                      _statusMessage = "";
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Clear All Fields"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}