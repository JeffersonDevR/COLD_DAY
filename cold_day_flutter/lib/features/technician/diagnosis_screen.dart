import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

/// RF-SR-004: el técnico asignado registra las observaciones del diagnóstico
/// antes de proponer el pacto (HU-SR-002).
class DiagnosisScreen extends StatefulWidget {
  final int requestId;

  const DiagnosisScreen({super.key, required this.requestId});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  final _observationsController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _observationsController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final observations = _observationsController.text.trim();
    if (observations.isEmpty) {
      _showMessage('Describe las observaciones del diagnóstico');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiClient.registerDiagnosis(
        requestId: widget.requestId,
        observations: observations,
      );
      if (!mounted) return;
      // El dashboard muestra el mensaje de éxito al recibir `true`.
      Navigator.pop(context, true);
    } catch (e) {
      _showMessage('Error al registrar el diagnóstico: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerLow,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Solicitud #${widget.requestId} — registrá qué encontraste en la visita:',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observationsController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Ej. Fuga de gas refrigerante en la línea de alta...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.assignment_turned_in),
                label: Text(
                  _submitting ? 'Guardando...' : 'Guardar diagnóstico',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}