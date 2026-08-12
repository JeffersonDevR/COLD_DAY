import 'package:flutter/material.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0A1632),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.construction, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              Text(
                'Próximamente',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF90CAF9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}