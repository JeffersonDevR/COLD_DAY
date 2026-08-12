import 'package:flutter/material.dart';
import 'package:cold_day_flutter/features/equipment/equipment_selection_screen.dart';

/// Pantalla final del flujo de cliente (flujo Luis Santander):
/// el pedido llega hasta la selección Residencial/Industrial y acá se confirma.
class RequestConfirmationScreen extends StatelessWidget {
  const RequestConfirmationScreen({
    super.key,
    required this.category,
    required this.technology,
    required this.sector,
  });

  final String category;
  final String? technology;
  final String sector;

  String get _sectorLabel =>
      sector == 'residential' ? 'Residencial' : 'Industrial';

  String get _techLabel => switch (technology) {
        'conventional' => 'Convencional',
        'inverter' => 'Inverter',
        _ => 'No aplica',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      appBar: AppBar(
        title: const Text('Solicitud'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              const Icon(
                Icons.check_circle_outline,
                size: 90,
                color: Colors.green,
              ),
              const SizedBox(height: 20),
              const Text(
                '¡Solicitud registrada!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D1B3E),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Un técnico te contactará pronto.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.blueGrey),
              ),
              const SizedBox(height: 28),

              // Resumen de la solicitud
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Equipo', value: category),
                      const SizedBox(height: 12),
                      _SummaryRow(label: 'Tecnología', value: _techLabel),
                      const SizedBox(height: 12),
                      _SummaryRow(label: 'Sector', value: _sectorLabel),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 2),

              // Volver: nueva solicitud
              SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const EquipmentSelectionScreen(),
                    ),
                    (route) => false,
                  ),
                  icon: const Icon(Icons.home),
                  label: const Text(
                    'Nueva solicitud',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D1B3E),
          ),
        ),
      ],
    );
  }
}