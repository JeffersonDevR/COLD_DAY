import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';

/// Decisión del cliente sobre un pacto propuesto (HU-SR-003).
enum PactReviewDecision { accept, reject }

/// Diálogo de revisión del Pacto de Servicio (RF-SR-005/006/007): muestra el
/// desglose labor + traslado + diagnóstico + total y las observaciones del
/// diagnóstico; devuelve la decisión del cliente.
class PactReviewDialog extends StatelessWidget {
  final Map<String, dynamic> agreement;

  const PactReviewDialog({super.key, required this.agreement});

  /// Abre el diálogo y resuelve con la decisión (null si se cierra sin elegir).
  static Future<PactReviewDecision?> show(
    BuildContext context, {
    required Map<String, dynamic> agreement,
  }) {
    return showDialog<PactReviewDecision>(
      context: context,
      builder: (ctx) => PactReviewDialog(agreement: agreement),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = (agreement['total'] as num?)?.toDouble() ?? 0;

    return AlertDialog(
      title: const Text('Pacto de servicio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revisá el desglose antes de aceptar:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _breakdownRow('Mano de obra', agreement['labor_cost']),
            _breakdownRow('Traslado', agreement['transport_cost']),
            _breakdownRow('Diagnóstico', agreement['diagnosis_cost']),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  formatCop(total),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (agreement['observations'] != null) ...[
              const SizedBox(height: 12),
              Text(
                'Diagnóstico: ${agreement['observations']}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context, PactReviewDecision.reject),
          icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
          label: Text(
            'Rechazar pacto',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
          ),
          onPressed: () => Navigator.pop(context, PactReviewDecision.accept),
          icon: const Icon(Icons.check_circle),
          label: const Text('Aceptar pacto'),
        ),
      ],
    );
  }

  Widget _breakdownRow(String label, dynamic value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            formatCop(amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}