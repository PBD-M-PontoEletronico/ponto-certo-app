class PoliticaSetor {
  final String setorId;
  final int toleranciaMinutos;
  final bool exigeSelfie;
  final int raioMetros;

  PoliticaSetor({
    required this.setorId,
    required this.toleranciaMinutos,
    required this.exigeSelfie,
    required this.raioMetros,
  });

  Map<String, dynamic> toMap() {
    return {
      'setorId': setorId,
      'toleranciaMinutos': toleranciaMinutos,
      'exigeSelfie': exigeSelfie ? 1 : 0,
      'raioMetros': raioMetros,
    };
  }

  factory PoliticaSetor.fromMap(Map<String, dynamic> map) {
    return PoliticaSetor(
      setorId: map['setorId'] as String,
      toleranciaMinutos: map['toleranciaMinutos'] as int,
      exigeSelfie: (map['exigeSelfie'] as int) == 1,
      raioMetros: map['raioMetros'] as int,
    );
  }
}