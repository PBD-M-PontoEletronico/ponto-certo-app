class MarcacaoRecente {
  final String dataHora; // ISO 8601
  final String tipo; // ENTRADA, SAIDA, etc.

  MarcacaoRecente({required this.dataHora, required this.tipo});

  Map<String, dynamic> toMap() {
    return {'dataHora': dataHora, 'tipo': tipo};
  }

  factory MarcacaoRecente.fromMap(Map<String, dynamic> map) {
    return MarcacaoRecente(
      dataHora: map['dataHora'] as String,
      tipo: map['tipo'] as String,
    );
  }
}