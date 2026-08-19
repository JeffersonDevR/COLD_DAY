import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

/// RF-SR-005: el técnico asignado propone el Pacto de Servicio con desglose
/// labor + traslado + diagnóstico y las observaciones del diagnóstico
/// (HU-SR-002). El total lo calcula el backend; acá se previsualiza.
class PactProposalScreen extends StatefulWidget {
  final int requestId;

  const PactProposalScreen({super.key, required this.requestId});

  @override
  State<PactProposalScreen> createState() => _PactProposalScreenState();
}

class _PactProposalScreenState extends State<PactProposalScreen> {
  final _laborController = TextEditingController(text: '80000');
  final _transportController = TextEditingController(text: '15000');
  final _diagnosisController = TextEditingController(text: '35000');
  final _observationsController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _laborController.dispose();
    _transportController.dispose();
    _diagnosisController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  double get _total {
    final labor = double.tryParse(_laborController.text) ?? 0;
    final transport = double.tryParse(_transportController.text) ?? 0;
    final diagnosis = double.tryParse(_diagnosisController.text) ?? 0;
    return labor + transport + diagnosis;
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final labor = double.tryParse(_laborController.text);
    final transport = double.tryParse(_transportController.text);
    final diagnosis = double.tryParse(_diagnosisController.text);
    if (labor == null ||
        labor < 0 ||
        transport == null ||
        transport < 0 ||
        diagnosis == null ||
        diagnosis < 0) {
      _showMessage('Los costos deben ser números mayores o iguales a 0');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiClient.proposeAgreement(
        requestId: widget.requestId,
        laborCost: labor,
        transportCost: transport,
        diagnosisCost: diagnosis,
        observations: _observationsController.text.trim().isEmpty
            ? null
            : _observationsController.text.trim(),
      );
      if (!mounted) return;
      // El dashboard muestra el mensaje de éxito al recibir `true`.
      Navigator.pop(context, true);
    } catch (e) {
      _showMessage('Error al proponer el pacto: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proponer Pacto'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3F2FD), Colors.white],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Solicitud #${widget.requestId} — desglose del pacto:',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _laborController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo de mano de obra (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _transportController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo de traslado (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _diagnosisController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo de diagnóstico (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _observationsController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Observaciones del diagnóstico (opcional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '\$${_total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.description),
                label: Text(
                  _submitting ? 'Proponiendo...' : 'Proponer pacto',
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