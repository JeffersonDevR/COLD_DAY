// Helpers puros del vertical de solicitudes (S3): etiquetas de estado en
// español (spec: "Estados de negocio en español en UI") y formato de fecha
// para el historial. Sin dependencias de UI para poder testearlos directo.
library;

/// Etiqueta en español para cada estado de la máquina PINNED (spec §3).
String requestStatusLabel(String status) {
  switch (status) {
    case 'requested':
      return 'Pendiente';
    case 'bidding':
      return 'En oferta';
    case 'diagnosis':
      return 'En diagnóstico';
    case 'pact_proposed':
      return 'Pacto propuesto';
    case 'in_progress':
      return 'En proceso';
    case 'completed':
      return 'Completada';
    case 'cancelled':
      return 'Cancelada';
    default:
      return status;
  }
}

/// Fecha legible (yyyy-mm-dd) a partir del ISO del backend; vacío si no hay.
String formatRequestDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final datePart = iso.split('T').first;
  return datePart;
}

/// Formatea un monto en COP: 15000 -> "$15.000".
String formatCop(num? value) {
  if (value == null) return '\$0';
  final intValue = value.round();
  final digits = intValue.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  final sign = intValue < 0 ? '-' : '';
  return '\$$sign$buffer';
}
