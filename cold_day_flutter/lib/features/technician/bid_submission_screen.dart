import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';

/// Formulario real de oferta (RF-TEC-006, RF-SR-002): el técnico envía el bid
/// con costos de traslado + diagnóstico (>= 0). El compromiso vinculante llega
/// cuando el cliente acepta el pacto, no con el bid.
class BidSubmissionScreen extends StatefulWidget {
  final int requestId;
  final String equipment;

  const BidSubmissionScreen({
    super.key,
    required this.requestId,
    required this.equipment,
  });

  @override
  State<BidSubmissionScreen> createState() => _BidSubmissionScreenState();
}

class _BidSubmissionScreenState extends State<BidSubmissionScreen> {
  final _transportController = TextEditingController(text: '15000');
  final _diagnosisController = TextEditingController(text: '35000');
  bool _submitting = false;

  @override
  void dispose() {
    _transportController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final transport = double.tryParse(_transportController.text);
    final diagnosis = double.tryParse(_diagnosisController.text);
    if (transport == null || transport < 0 || diagnosis == null || diagnosis < 0) {
      _showMessage('Los costos deben ser números mayores o iguales a 0');
      return;
    }

    setState(() => _submitting = true);
    try {
      // RF-SR-002: el bid viaja con los costos; el técnico sale del token.
      await ApiClient.sendTechnicianBid(
        serviceRequestId: widget.requestId,
        priceOffered: transport + diagnosis,
        estimatedTimeMinutes: 45,
        transportCost: transport,
        diagnosisCost: diagnosis,
      );
      if (!mounted) return;
      // El dashboard muestra el mensaje de éxito al recibir `true`.
      Navigator.pop(context, true);
    } catch (e) {
      _showMessage('Error al enviar la oferta: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enviar Oferta'),
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
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: ListTile(
                leading: Icon(Icons.ac_unit, color: Theme.of(context).colorScheme.primary),
                title: Text(widget.equipment),
                subtitle: Text('Solicitud #${widget.requestId}'),
              ),
            ),
            const SizedBox(height: 20),
            Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _transportController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Costo de traslado (COP)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _diagnosisController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Costo de diagnóstico (COP)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
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
                          : const Icon(Icons.handshake),
                      label: Text(
                        _submitting ? 'Enviando oferta...' : 'Enviar oferta',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
