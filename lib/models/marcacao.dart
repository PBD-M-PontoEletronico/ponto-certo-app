/// Uma marcação de ponto batida pelo funcionário no aparelho.
/// Diferente de MarcacaoRecente (histórico vindo do servidor), esta
/// representa uma marcação feita agora, localmente, que ainda
/// precisa ser enviada (fila real é escopo da APP 07).
class Marcacao {
  final String id; // gerado no aparelho, único
  final String tipo; // ENTRADA, SAIDA_INTERVALO, RETORNO_INTERVALO, SAIDA
  final String dataHora; // ISO 8601 — horário exato do toque, não do envio

  Marcacao({
    required this.id,
    required this.tipo,
    required this.dataHora,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'tipo': tipo, 'dataHora': dataHora};
  }

  factory Marcacao.fromMap(Map<String, dynamic> map) {
    return Marcacao(
      id: map['id'] as String,
      tipo: map['tipo'] as String,
      dataHora: map['dataHora'] as String,
    );
  }
}