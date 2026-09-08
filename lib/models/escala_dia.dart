class EscalaDia {
  final String data; // formato ISO: yyyy-MM-dd
  final String horaInicio;
  final String horaFim;

  EscalaDia({
    required this.data,
    required this.horaInicio,
    required this.horaFim,
  });

  Map<String, dynamic> toMap() {
    return {'data': data, 'horaInicio': horaInicio, 'horaFim': horaFim};
  }

  factory EscalaDia.fromMap(Map<String, dynamic> map) {
    return EscalaDia(
      data: map['data'] as String,
      horaInicio: map['horaInicio'] as String,
      horaFim: map['horaFim'] as String,
    );
  }
}