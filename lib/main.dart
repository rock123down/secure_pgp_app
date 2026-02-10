import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'encryption_service.dart';

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
  // Shared Controllers/State
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _result = "";
  String _statusMessage = "";
  int _selectedDrawerIndex = 0;

  void _copyToClipboard() {
    if (_result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _result));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Copied to clipboard!"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleEncrypt() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _statusMessage = "Error: Password required");
      return;
    }
    final encrypted = await EncryptionService.encryptSymmetric(
        _textController.text, _passwordController.text);
    setState(() {
      _result = encrypted;
      _statusMessage = "Encrypted successfully";
    });
  }

  void _handleDecrypt() async {
    String source = _textController.text.contains("-----BEGIN PGP")
        ? _textController.text
        : _result;
    if (!source.contains("-----BEGIN PGP")) {
      setState(() => _statusMessage = "Error: No PGP message found");
      return;
    }
    final decrypted = await EncryptionService.decryptSymmetric(
        source, _passwordController.text);
    setState(() {
      _result = decrypted;
      _statusMessage = "Decryption successful";
    });
  }

  @override
  Widget build(BuildContext context) {
    // FIX: DefaultTabController must wrap the Scaffold to provide
    // the coordinate system for TabBar and TabBarView.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedDrawerIndex == 0
              ? "🔐 Secure PGP Vault"
              : "🔑 Key Management"),
          centerTitle: true,
          // Only show TabBar if the "Vault" (index 0) is selected
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
            _buildActionPage(isEncrypt: true),
            _buildActionPage(isEncrypt: false),
          ],
        )
            : _buildKeysScreen(),
      ),
    );
  }

  Widget _buildActionPage({required bool isEncrypt}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _textController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText:
                  isEncrypt ? "Text to Encrypt" : "PGP Message to Decrypt",
                  hintText: isEncrypt
                      ? "Enter secret message..."
                      : "-----BEGIN PGP MESSAGE-----...",
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: "Password", prefixIcon: Icon(Icons.key)),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: isEncrypt ? _handleEncrypt : _handleDecrypt,
                icon: Icon(isEncrypt ? Icons.security : Icons.vpn_key),
                label: Text(isEncrypt ? "Encrypt Data" : "Decrypt Data"),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const SizedBox(height: 24),
              _buildResultSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("RESULT",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            if (_result.isNotEmpty)
              IconButton(icon: const Icon(Icons.copy), onPressed: _copyToClipboard),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(minHeight: 100, maxHeight: 200),
          child: SingleChildScrollView(
              child: SelectableText(_result,
                  style: const TextStyle(fontFamily: 'monospace'))),
        ),
        if (_statusMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_statusMessage,
                style: TextStyle(
                    color: _statusMessage.contains("Error")
                        ? Colors.red
                        : Colors.green)),
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
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Icon(Icons.security, size: 48),
                  SizedBox(height: 10),
                  Text("PGP Vault v1.0",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
    final List<Map<String, String>> mockKeys = [
      {"name": "John Doe", "id": "0x8F2D1A", "type": "Private/Public"},
      {"name": "Jane Smith", "id": "0x3C4B92", "type": "Public Key"}, // Fixed typo 'is' to 'id'
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: mockKeys.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: Text(mockKeys[index]['name']!),
                    subtitle: Text(
                        "ID: ${mockKeys[index]['id']} • ${mockKeys[index]['type']}"),
                    trailing: const Icon(Icons.more_vert),
                  ),
                );
              },
            ),
          ),
          FloatingActionButton.extended(
            onPressed: () {
              // Logic for generating a new key pair will go here
            },
            label: const Text("Generate New Key"),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}