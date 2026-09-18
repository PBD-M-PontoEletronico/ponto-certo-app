/// O que fazer quando uma marcação de ponto acontece fora do
/// perímetro do setor: bloquear, ou aceitar como pendente de análise.
/// Os valores espelham exatamente o enum PoliticaForaPerimetro.java
/// do backend — não mude os nomes sem checar lá também.
enum PoliticaForaPerimetro {
  bloquear,
  pendenteAnalise;

  static PoliticaForaPerimetro fromApi(String valor) {
    switch (valor) {
      case 'BLOQUEAR':
        return PoliticaForaPerimetro.bloquear;
      case 'PENDENTE_ANALISE':
        return PoliticaForaPerimetro.pendenteAnalise;
      default:
        throw ArgumentError(
          'Valor de politicaForaPerimetro desconhecido: $valor',
        );
    }
  }

  String toApi() {
    switch (this) {
      case PoliticaForaPerimetro.bloquear:
        return 'BLOQUEAR';
      case PoliticaForaPerimetro.pendenteAnalise:
        return 'PENDENTE_ANALISE';
    }
  }
}

/// Política de marcação do setor — o que muda de setor para setor.
/// Reflete os campos reais gravados na API (model/Setor.java):
/// raioMetros, exigirSelfie, politicaForaPerimetro, ignorarLocalizacao.
class PoliticaSetor {
  final String setorId;
  final int raioMetros;
  final bool exigirSelfie;
  final PoliticaForaPerimetro politicaForaPerimetro;
  final bool ignorarLocalizacao;

  PoliticaSetor({
    required this.setorId,
    required this.raioMetros,
    required this.exigirSelfie,
    required this.politicaForaPerimetro,
    required this.ignorarLocalizacao,
  });

  Map<String, dynamic> toMap() {
    return {
      'setorId': setorId,
      'raioMetros': raioMetros,
      'exigirSelfie': exigirSelfie ? 1 : 0,
      'politicaForaPerimetro': politicaForaPerimetro.toApi(),
      'ignorarLocalizacao': ignorarLocalizacao ? 1 : 0,
    };
  }

  factory PoliticaSetor.fromMap(Map<String, dynamic> map) {
    return PoliticaSetor(
      setorId: map['setorId'] as String,
      raioMetros: map['raioMetros'] as int,
      exigirSelfie: (map['exigirSelfie'] as int) == 1,
      politicaForaPerimetro: PoliticaForaPerimetro.fromApi(
        map['politicaForaPerimetro'] as String,
      ),
      ignorarLocalizacao: (map['ignorarLocalizacao'] as int) == 1,
    );
  }
}