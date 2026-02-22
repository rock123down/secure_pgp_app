import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'encryption_service.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const EncryptionApp());
}

class EncryptionApp extends StatelessWidget {
  const EncryptionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
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
  final List<Map<String, String>> _myKeys = [];
  Map<String, String>? _selectedKey;
  final TextEditingController _encryptTextController = TextEditingController();
  final TextEditingController _decryptTextController = TextEditingController();

  // Initialize Secure storage
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _encryptResult = "";
  String _decryptResult = "";
  String _encryptStatus = "";
  String _decryptStatus = "";
  int _selectedDrawerIndex = 0;

  // Timers for Encryption Tab
  Timer? _encryptAutoClearTimer;
  Timer? _encryptCountdownTimer;
  int _encryptSecondsRemaining = 0;

  // Timers for Decryption Tab
  Timer? _decryptAutoClearTimer;
  Timer? _decryptCountdownTimer;
  int _decryptSecondsRemaining = 0;

  bool _isLoadingKeys = true;

  @override
  void initState() {
    super.initState();
    _loadKeysFromStorage(); // Load Keys as soon as the app starts
  }

  // IMPORT KEYS LOGIC

  Future<void> _handleImportBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pgp', 'keys', 'asc', 'key'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String encryptedData = await file.readAsString();

        await _importBackup(encryptedData);
      } else {
        debugPrint("User canceled file selection");
      }
    } catch (e) {
      _showErrorSheet("Failed to read file: $e");
    }
  }

  // --- SECURE BACKUP LOGIC ---
  Future<void> _backupKeys() async {
    if (_myKeys.isEmpty) {
      _showErrorSheet("No keys found to backup.");
      return;
    }

    // Reuse your passphrase UI to get a password for the backup file
    _promptForPassword((backupPassword) async {
      if (backupPassword.isEmpty) {
        _showErrorSheet("A password is required to encrypt the backup file.");
        return;
      }

      try {
        // 1. Convert keys to JSON string
        String jsonContent = jsonEncode(_myKeys);

        // 2. Encrypt the entire JSON string using the backup password
        String encryptedBackup = await EncryptionService.encryptSymmetric(
            jsonContent, backupPassword);

        // 3. Find path and save as .pgp (unreadable by text editors)
        final directory = await getApplicationDocumentsDirectory();
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final File file = File('${directory.path}/vault_backup_$timestamp.pgp');

        await file.writeAsString(encryptedBackup);

        _showBackupSuccessDialog(file.path);
      } catch (e) {
        _showErrorSheet("Backup failed: $e");
      }
    });
  }

  // --- RESTORE LOGIC ---
  Future<void> _importBackup(String encryptedData) async {
    _promptForPassword((password) async {
      try {
        // 1. Decrypt the symmetric wrapper
        String decryptedJson = await EncryptionService.decryptSymmetric(
            encryptedData, password);

        // 2. Parse the JSON
        List<dynamic> decoded = jsonDecode(decryptedJson);
        List<Map<String, String>> importedKeys = decoded.map((item) {
          return Map<String, String>.from(item as Map);
        }).toList();

        // 3. Merge keys and save
        setState(() {
          // Check for duplicates by ID before adding if desired
          _myKeys.addAll(importedKeys);
        });
        await _saveKeysToStorage();

        _showSuccessSheet("${importedKeys.length} keys imported successfully!");
      } catch (e) {
        _showErrorSheet("Restore failed. Incorrect password or corrupted file.");
      }
    });
  }

  // --- UI HELPER FOR BACKUP PATH ---
  void _showBackupSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.green),
            SizedBox(width: 10),
            Text("Encrypted Backup"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Your vault is now encrypted and saved at:"),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black,
              child: SelectableText(path, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
            ),
            const SizedBox(height: 10),
            const Text("The file is unreadable without your backup password.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  // SAVE logic
  Future<void> _saveKeysToStorage() async {
    try {
      String jsonKeys = jsonEncode(_myKeys);
      await _storage.write(
        key: 'pgp_keys',
        value: jsonKeys,
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );
      debugPrint("Keys saved to secure storage.");
    } catch (e) {
      debugPrint("Error saving keys: $e");
    }
  }

  // LOAD logic
  Future<void> _loadKeysFromStorage() async {
    setState(() => _isLoadingKeys = true);

    try {
      // Small delay to ensure Android KeyStore is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));

      final jsonKeys = await _storage.read(
        key: 'pgp_keys',
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );

      if (jsonKeys != null && jsonKeys.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonKeys);

        // Ensure we are creating a fresh list of strict String maps
        final List<Map<String, String>> freshKeys = decoded.map((item) {
          return Map<String, String>.from(item as Map);
        }).toList();

        if (mounted) {
          setState(() {
            _myKeys.clear();
            _myKeys.addAll(freshKeys);

            // NEW: Auto-select the first key if none is currently selected
            if (_myKeys.isNotEmpty && _selectedKey == null) {
              _selectedKey = _myKeys.first;
            }

            _isLoadingKeys = false;
          });
          debugPrint("Successfully loaded ${_myKeys.length} keys and updated selection.");
        }
      } else {
        if (mounted) setState(() => _isLoadingKeys = false);
        debugPrint("No keys found in secure storage.");
      }
    } catch (e) {
      debugPrint("CRITICAL STORAGE ERROR: $e");
      if (mounted) setState(() => _isLoadingKeys = false);
    }
  }

  @override
  void dispose() {
    // FIX: Cancel all specific timers
    _encryptAutoClearTimer?.cancel();
    _encryptCountdownTimer?.cancel();
    _decryptAutoClearTimer?.cancel();
    _decryptCountdownTimer?.cancel();
    _encryptTextController.dispose();
    _decryptTextController.dispose();
    super.dispose();
  }

  void _startClearTimer(bool isEncrypt) {
    if (isEncrypt) {
      _encryptAutoClearTimer?.cancel();
      _encryptCountdownTimer?.cancel();
      setState(() => _encryptSecondsRemaining = 30);

      _encryptCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _encryptSecondsRemaining > 0) {
          setState(() {
            _encryptSecondsRemaining--;
            _encryptStatus = "Data will clear in ${_encryptSecondsRemaining}s";
          });
        } else {
          timer.cancel();
        }
      });

      _encryptAutoClearTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _encryptResult = "";
            _encryptStatus = "Cleared for security";
            _encryptTextController.clear();
          });
        }
      });
    } else {
      _decryptAutoClearTimer?.cancel();
      _decryptCountdownTimer?.cancel();
      setState(() => _decryptSecondsRemaining = 30);

      _decryptCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _decryptSecondsRemaining > 0) {
          setState(() {
            _decryptSecondsRemaining--;
            _decryptStatus = "Data will clear in ${_decryptSecondsRemaining}s";
          });
        } else {
          timer.cancel();
        }
      });

      _decryptAutoClearTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _decryptResult = "";
            _decryptStatus = "Cleared for security";
            _decryptTextController.clear();
          });
        }
      });
    }
  }

  void _handleEncrypt() {
    if (_encryptTextController.text.isEmpty) {
      setState(() => _encryptStatus = "Error: Enter text first");
      return;
    }

    _promptForPassword((password) async {
      String encrypted;
      if (_selectedKey != null) {
        encrypted = await EncryptionService.encryptAsymmetric(
            _encryptTextController.text, _selectedKey!['publicKey']!);
      } else {
        encrypted = await EncryptionService.encryptSymmetric(
            _encryptTextController.text, password);
      }

      setState(() {
        _encryptResult = encrypted;
        _encryptStatus = "Encrypted successfully";
      });
      _startClearTimer(true);
    });
  }

  void _handleDecrypt() {
    if (_decryptTextController.text.isEmpty) {
      setState(() => _decryptStatus = "Error: Enter PGP message");
      return;
    }

    _promptForPassword((password) async {
      String decrypted;
      if (_selectedKey != null) {
        decrypted = await EncryptionService.decryptAsymmetric(
          _decryptTextController.text,
          _selectedKey!['privateKey']!,
          password,
        );
      } else {
        decrypted = await EncryptionService.decryptSymmetric(
          _decryptTextController.text,
          password,
        );
      }

      setState(() {
        _decryptResult = decrypted;
        _decryptStatus = "Decrypted Successfully";
      });
      _startClearTimer(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedDrawerIndex == 0 ? "🔐 Secure PGP Vault" : "🔑 Key Management"),
          centerTitle: true,
          bottom: _selectedDrawerIndex == 0
              ? const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.lock), text: "Encrypt"),
              Tab(icon: Icon(Icons.lock_open), text: "Decrypt"),
            ],
          )
              : null,
        ),
        drawer: _buildSideMenu(),
        body: _selectedDrawerIndex == 0
            ? TabBarView(
          children: [
            _buildActionPage(
                isEncrypt: true,
                result: _encryptResult,
                status: _encryptStatus,
                seconds: _encryptSecondsRemaining),
            _buildActionPage(
                isEncrypt: false,
                result: _decryptResult,
                status: _decryptStatus,
                seconds: _decryptSecondsRemaining),
          ],
        )
            : _buildKeysScreen(),
      ),
    );
  }

  Widget _buildActionPage(
      {required bool isEncrypt,
        required String result,
        required String status,
        required int seconds}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<Map<String, String>>(
                initialValue: _myKeys.contains(_selectedKey) ? _selectedKey : null,
                decoration: InputDecoration(
                  labelText: isEncrypt ? "Select Recipient's Public Key" : "Select Your Private Key",
                  prefixIcon: const Icon(Icons.vpn_key),
                ),
                items: _myKeys.map((key) {
                  return DropdownMenuItem(
                    value: key,
                    child: Text("${key['name']} (${key['id']})"),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedKey = value);
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: isEncrypt ? _encryptTextController : _decryptTextController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: isEncrypt ? "Text to Encrypt" : "PGP Message to Decrypt",
                  hintText: isEncrypt ? "Enter secret message..." : "-----BEGIN PGP MESSAGE-----",
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: isEncrypt ? _handleEncrypt : _handleDecrypt,
                icon: Icon(isEncrypt ? Icons.security : Icons.vpn_key),
                label: Text(isEncrypt ? "Encrypt Data" : "Decrypt Data"),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const SizedBox(height: 24),
              // FIX: Now passing all 3 required arguments
              _buildResultSection(result, status, seconds),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection(String currentResult, String status, int seconds) {
    if (currentResult.isEmpty) {
      return status.isNotEmpty
          ? Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          status,
          style: TextStyle(
            color: status.contains("Error") ? Colors.red : Colors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
      )
          : const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seconds > 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  "Security Wipe in ${seconds}s", // FIX: Use local 'seconds' parameter
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: seconds / 30, // FIX: Use local 'seconds' parameter
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    seconds < 10 ? Colors.redAccent : Colors.blueGrey,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("RESULT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: currentResult));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Copied to clipboard!"), behavior: SnackBarBehavior.floating),
                );
              },
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(minHeight: 100, maxHeight: 200),
          child: SingleChildScrollView(
            child: SelectableText(
              currentResult,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              status,
              style: TextStyle(
                color: status.contains("Error") ? Colors.red : Colors.green,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSideMenu() {
    return Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.security, size: 48),
                  SizedBox(height: 10),
                  Text("PGP Vault v1.0", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.vignette),
              title: const Text("Vault"),
              selected: _selectedDrawerIndex == 0,
              onTap: () {
                setState(() => _selectedDrawerIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text("Keys"),
              selected: _selectedDrawerIndex == 1,
              onTap: () {
                setState(() => _selectedDrawerIndex = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text("Backup all Keys"),
              onTap: () {
                Navigator.pop(context);
                _backupKeys();
              }
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text("Import Backup"),
              onTap: () async {
                Navigator.pop(context);
                _handleImportBackup();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("Settings"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ));
  }

  Widget _buildKeysScreen() {
    if (_isLoadingKeys) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: _myKeys.isEmpty
                ? const Center(child: Text("No keys generated yet. Click + to start."))
                : ListView.builder(
              itemCount: _myKeys.length,
              itemBuilder: (context, index) {
                final keyItem = _myKeys[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: Text(keyItem['name']!),
                    subtitle: Text("ID: ${keyItem['id']} • ${keyItem['type']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline, color: Colors.blueAccent,),
                          onPressed: () => _showKeyInfo(_myKeys[index]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _confirmDeleteKey(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          FloatingActionButton.extended(
            onPressed: () => _showKeyGenerationDialog(),
            label: const Text("Generate New Key"),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _showKeyGenerationDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        // We use a StatefulBuilder to refresh the error message inside the dialog
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String? errorMessage;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.key_rounded, color: Colors.blueGrey),
                  SizedBox(width: 10),
                  Text("Generate Key Pair"),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Create a new identity. The password is required to secure your private key.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: "Email Address",
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password",
                        prefixIcon: Icon(Icons.lock_outline),
                        hintText: "Don't leave this blank",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // VALIDATION: Similar logic to your Passphrase prompt
                    if (nameController.text.isEmpty ||
                        emailController.text.isEmpty ||
                        passController.text.isEmpty) {

                      // Show an error bottom sheet instead of a snackbar
                      _showErrorSheet("All fields are required to generate a secure key.");
                      return;
                    }

                    // Show loading
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final keyPair = await EncryptionService.generateKeyPair(
                          nameController.text,
                          emailController.text,
                          passController.text
                      );

                      setState(() {
                        _myKeys.add({
                          "name": nameController.text,
                          "id": "0x${keyPair.publicKey.hashCode.toRadixString(16).toLowerCase()}",
                          "type": "Private/Public",
                          "publicKey": keyPair.publicKey,
                          "privateKey": keyPair.privateKey,
                        });
                      });

                      await _saveKeysToStorage();

                      Navigator.pop(context); // Pop loading
                      Navigator.pop(context); // Pop generation dialog

                      _showSuccessSheet("Key Pair Generated Successfully");
                    } catch (e) {
                      Navigator.pop(context); // Pop loading
                      _showErrorSheet("Generation failed: $e");
                    }
                  },
                  child: const Text("Generate"),
                ),
              ],
            );
          },
        );
      },
    );
  }

// Add these helper methods for a consistent "Passphrase UI" feel
  void _showErrorSheet(String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.red[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 40),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showSuccessSheet(String message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 40),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _promptForPassword(Function(String) onPasswordEntered) {
    final TextEditingController popupPassController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
        EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter Passphrase",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: popupPassController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Password/Passphrase",
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onPasswordEntered(popupPassController.text);
              },
              child: const Text("Confirm"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteKey(int index) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Delete Key Pair?"),
      content: Text("Are you sure you want to delete '${_myKeys[index]['name']}'? This action cannot be undone."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
            onPressed: () async {
              Navigator.pop(context);
              await _deleteKey(index);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
            ),
      ],
    ),
    );
  }

  Future<void> _deleteKey(int index) async {
    setState(() {
      if (_selectedKey == _myKeys[index]) {
        _selectedKey = null;
      }
      _myKeys.removeAt(index);
    });

    await _saveKeysToStorage();

    _showSuccessSheet("Key deleted successfully");
  }

  void _showKeyInfo(Map<String, String> keyData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: const BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const Text("Key Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _infoTile("Name", keyData['name']!),
                _infoTile("Key ID", keyData['id']!),
                _infoTile("Type", keyData['type']!),
                const Divider(height: 30),
                const Text("Public Key Block", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: SelectableText(
                    keyData['publicKey']!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: keyData['publicKey']!));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Public Key Block"),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String label, value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey),),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

}