import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const QRShieldTesterApp());
}

class QRShieldTesterApp extends StatelessWidget {
  const QRShieldTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QRShield Tester',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueAccent,
        useMaterial3: true,
      ),
      home: const TestingScreen(),
    );
  }
}

class TestingScreen extends StatefulWidget {
  const TestingScreen({super.key});

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String _backendUrl = "http://127.0.0.1:8000/scan";

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = null;
      });
      _analyzeImage();
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          _image!.path,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() {
          _result = json.decode(response.body);
        });
      } else {
        setState(() {
          _result = {"error": "Server error: ${response.statusCode}", "body": response.body};
        });
      }
    } catch (e) {
      setState(() {
        _result = {"error": "Connection failed: $e"};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRShield Backend Tester'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onChanged: (val) => _backendUrl = val,
              controller: TextEditingController(text: _backendUrl),
            ),
            const SizedBox(height: 24),
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: _image != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_image!, fit: BoxFit.cover),
              )
                  : const Center(
                child: Text('No image selected', style: TextStyle(color: Colors.grey)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.image),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_result != null)
              _buildResultCard()
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final status = _result!['status'] ?? 'UNKNOWN';
    final isSafe = status == 'SAFE';
    final isMalicious = status == 'MALICIOUS' || status == 'DISTORTED_QR';
    
    Color color = Colors.orange;
    if (isSafe) color = Colors.green;
    if (isMalicious) color = Colors.red;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('STATUS: $status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Icon(isSafe ? Icons.check_circle : (isMalicious ? Icons.gpp_bad : Icons.warning), color: color),
              ],
            ),
            const Divider(height: 24),
            _resultItem('URL', _result!['decoded_url'] ?? 'Not found'),
            _resultItem('Fusion Score', _result!['fusion_score']?.toString() ?? 'N/A'),
            _resultItem('DL Prob (Image)', _result!['dl_probability']?.toString() ?? 'N/A'),
            _resultItem('ML Prob (URL)', _result!['ml_probability']?.toString() ?? 'N/A'),
            _resultItem('Mode', _result!['fusion_mode'] ?? 'N/A'),
            if (_result!['note'] != null)
              _resultItem('Note', _result!['note']!),
            if (_result!['error'] != null)
              _resultItem('Error', _result!['error']!, isError: true),
          ],
        ),
      ),
    );
  }

  Widget _resultItem(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            TextSpan(text: value, style: TextStyle(color: isError ? Colors.redAccent : Colors.white)),
          ],
        ),
      ),
    );
  }
}
