class Funcionario {
  final String id;
  final String nome;
  final String usuario;
  final String perfil;
  final List<String> setoresIds;

  Funcionario({
    required this.id,
    required this.nome,
    required this.usuario,
    required this.perfil,
    required this.setoresIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'usuario': usuario,
      'perfil': perfil,
      // Lista salva como string separada por vírgula (SQLite não tem tipo lista nativo)
      'setoresIds': setoresIds.join(','),
    };
  }

  factory Funcionario.fromMap(Map<String, dynamic> map) {
    return Funcionario(
      id: map['id'] as String,
      nome: map['nome'] as String,
      usuario: map['usuario'] as String,
      perfil: map['perfil'] as String,
      setoresIds: (map['setoresIds'] as String)
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}