import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class PqrScreen extends StatelessWidget {
  const PqrScreen({super.key});

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      appBar: AppBar(
        title: const Text('PQR · Quejas y reclamos'),
        backgroundColor: const Color(0xFF0A1632),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.support_agent, size: 80, color: Color(0xFF8FB9A9)),
              const SizedBox(height: 20),
              const Text(
                '¿Tuviste un problema con un servicio?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Nuestro servicio al cliente y nuestros técnicos te ayudarán a solucionar el error. Contactanos por WhatsApp para brindarte atención.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF8FB9A9)),
              ),
              const SizedBox(height: 32),

              // WhatsApp (enlace de copiado en MVP)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  const number = '3000000000';
                  Clipboard.setData(ClipboardData(text: number));
                  _showSnack(
                    context,
                    'Número copiado: $number (enlace de WhatsApp próximamente)',
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text(
                  'Contactar por WhatsApp',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),

              // Llamar
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  const number = '300 000 0000';
                  Clipboard.setData(ClipboardData(text: number));
                  _showSnack(context, 'Teléfono copiado: $number');
                },
                icon: const Icon(Icons.phone),
                label: const Text(
                  'Llamar a servicio al cliente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}