import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';

/// Calificación post-servicio (RF-RAT-007, HU-RAT-001): el cliente dueño evalúa
/// las 3 sub-dimensiones (puntualidad, calidad, profesionalismo) en escala 1-5
/// y opcionalmente deja un comentario (<= 1000 caracteres, validado por el
/// backend). Al enviar, POST /api/services/{id}/review/ (RF-RAT-001..003).
///
/// Se abre desde el detalle del historial del cliente cuando la solicitud está
/// `completed`. En éxito cierra con `true` para que la pantalla anterior
/// refresque y oculte la acción; en error (p.ej. 409 ya calificado) muestra el
/// detalle y permanece abierta.
class RatingScreen extends StatefulWidget {
  final int requestId;
  final String? technicianName;

  const RatingScreen({super.key, required this.requestId, this.technicianName});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  static const int _maxCommentLength = 1000;

  int _punctuality = 5;
  int _quality = 5;
  int _professionalism = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ApiClient.submitReview(
        requestId: widget.requestId,
        punctuality: _punctuality,
        quality: _quality,
        professionalism: _professionalism,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true); // historial: refresca y oculta la acción
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar la calificación: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificar servicio'),
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
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Cómo fue el servicio?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (widget.technicianName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Técnico: ${widget.technicianName}',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _StarSelector(
                      label: 'Puntualidad',
                      keyPrefix: 'puntualidad',
                      value: _punctuality,
                      onChanged: (v) => setState(() => _punctuality = v),
                    ),
                    _StarSelector(
                      label: 'Calidad',
                      keyPrefix: 'calidad',
                      value: _quality,
                      onChanged: (v) => setState(() => _quality = v),
                    ),
                    _StarSelector(
                      label: 'Profesionalismo',
                      keyPrefix: 'profesionalismo',
                      value: _professionalism,
                      onChanged: (v) => setState(() => _professionalism = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('comentario'),
              controller: _commentController,
              maxLength: _maxCommentLength,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                hintText: 'Contanos cómo te fue...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.star),
                label: const Text('Enviar calificación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de 5 estrellas para una sub-dimensión (1-5, RF-RAT-002). Cada estrella
/// lleva `Key('$keyPrefix-$value')` para que los tests ajusten el puntaje.
class _StarSelector extends StatelessWidget {
  final String label;
  final String keyPrefix;
  final int value;
  final ValueChanged<int> onChanged;

  const _StarSelector({
    required this.label,
    required this.keyPrefix,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (var star = 1; star <= 5; star++)
            IconButton(
              key: Key('$keyPrefix-$star'),
              iconSize: 28,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => onChanged(star),
              icon: Icon(
                star <= value ? Icons.star : Icons.star_border,
                color: Colors.amber.shade700,
              ),
            ),
        ],
      ),
    );
  }
}