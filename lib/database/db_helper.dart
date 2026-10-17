import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

import '../utils/helpers.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Future<Database>? _dbFuture;
  Future<Database> get database => _dbFuture ??= _abrir();

  Future<Database> _abrir() async {
    final caminho = join(await getDatabasesPath(), 'petshop_manager.db');
    return openDatabase(
      caminho,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _criar,
    );
  }

  Future<void> _criar(Database db, int versao) async {
    await db.execute('''
CREATE TABLE produtos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  codigo TEXT NOT NULL COLLATE NOCASE UNIQUE,
  nome TEXT NOT NULL CHECK (length(trim(nome)) > 0),
  categoria TEXT NOT NULL,
  marca TEXT,
  preco_custo REAL NOT NULL CHECK (preco_custo >= 0),
  preco_venda REAL NOT NULL CHECK (preco_venda >= 0),
  quantidade INTEGER NOT NULL DEFAULT 0 CHECK (quantidade >= 0),
  estoque_minimo INTEGER NOT NULL DEFAULT 0 CHECK (estoque_minimo >= 0),
  ativo INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1)),
  justificativa_preco TEXT
)''');
    await db.execute('''
CREATE TABLE clientes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL CHECK (length(trim(nome)) > 0),
  telefone TEXT,
  email TEXT,
  endereco TEXT,
  ativo INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1))
)''');
    await db.execute('''
CREATE TABLE vendas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id INTEGER NOT NULL,
  data_venda TEXT NOT NULL,
  valor_total REAL NOT NULL CHECK (valor_total >= 0),
  status TEXT NOT NULL CHECK (status IN ('CONFIRMADA', 'CANCELADA')),
  FOREIGN KEY (cliente_id) REFERENCES clientes (id)
)''');
    await db.execute('''
CREATE TABLE itens_venda (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  venda_id INTEGER NOT NULL,
  produto_id INTEGER NOT NULL,
  quantidade INTEGER NOT NULL CHECK (quantidade > 0),
  preco_unitario REAL NOT NULL CHECK (preco_unitario >= 0),
  subtotal REAL NOT NULL CHECK (subtotal >= 0),
  FOREIGN KEY (venda_id) REFERENCES vendas (id) ON DELETE CASCADE,
  FOREIGN KEY (produto_id) REFERENCES produtos (id)
)''');
    await db.execute('''
CREATE TABLE movimentacoes_estoque (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  produto_id INTEGER NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('ENTRADA', 'SAIDA', 'CANCELAMENTO')),
  quantidade INTEGER NOT NULL CHECK (quantidade > 0),
  data_movimentacao TEXT NOT NULL,
  observacao TEXT,
  FOREIGN KEY (produto_id) REFERENCES produtos (id)
)''');
    await db.execute('CREATE INDEX idx_itens_venda ON itens_venda (venda_id)');
    await db.execute('CREATE INDEX idx_mov_produto ON movimentacoes_estoque (produto_id)');
  }

  Future<void> _mov(DatabaseExecutor ex, int produtoId, String tipo, int qtd, String obs) async {
    await ex.insert('movimentacoes_estoque', {
      'produto_id': produtoId,
      'tipo': tipo,
      'quantidade': qtd,
      'data_movimentacao': DateTime.now().toIso8601String(),
      'observacao': obs,
    });
  }

  Future<List<Linha>> listarProdutos({String busca = '', bool apenasAtivos = false}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (apenasAtivos) where.add('ativo = 1');
    if (busca.trim().isNotEmpty) {
      where.add('(nome LIKE ? OR codigo LIKE ? OR categoria LIKE ? OR marca LIKE ?)');
      final b = '%${busca.trim()}%';
      args.addAll([b, b, b, b]);
    }
    return db.query(
      'produtos',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Linha>> listarEstoqueBaixo() async {
    final db = await database;
    return db.query(
      'produtos',
      where: 'ativo = 1 AND quantidade <= estoque_minimo',
      orderBy: 'quantidade, nome COLLATE NOCASE',
    );
  }

  void _validarProduto(Linha p) {
    final nome = ((p['nome'] as String?) ?? '').trim();
    final codigo = ((p['codigo'] as String?) ?? '').trim();
    final categoria = ((p['categoria'] as String?) ?? '').trim();
    final custo = (p['preco_custo'] as num?)?.toDouble();
    final venda = (p['preco_venda'] as num?)?.toDouble();
    final qtd = (p['quantidade'] as int?) ?? 0;
    final minimo = (p['estoque_minimo'] as int?) ?? 0;
    if (nome.isEmpty) throw AppException('Informe o nome do produto.'); // RN01
    if (codigo.isEmpty) throw AppException('Informe o código do produto.');
    if (categoria.isEmpty) throw AppException('Informe a categoria do produto.');
    if (custo == null || venda == null || custo < 0 || venda < 0) {
      throw AppException('Os preços não podem ser negativos.'); // RN01
    }
    if (qtd < 0 || minimo < 0) {
      throw AppException('Quantidade e estoque mínimo não podem ser negativos.');
    }
  }

  Future<int> salvarProduto(Linha p, {int? id}) async {
    _validarProduto(p);
    final db = await database;
    final dados = Map<String, Object?>.from(p)
      ..['codigo'] = (p['codigo'] as String).trim()
      ..['nome'] = (p['nome'] as String).trim()
      ..['marca'] = ((p['marca'] as String?) ?? '').trim();
    try {
      if (id != null) {
        dados.remove('quantidade');
        final n = await db.update('produtos', dados, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw AppException('Produto não encontrado.');
        return id;
      }
      return await db.transaction<int>((txn) async {
        dados['ativo'] = 1;
        final novoId = await txn.insert('produtos', dados);
        final qtd = (p['quantidade'] as int?) ?? 0;
        if (qtd > 0) {
          await _mov(txn, novoId, 'ENTRADA', qtd, 'Estoque inicial');
        }
        return novoId;
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw AppException('Já existe um produto com o código "${dados['codigo']}".'); // RN02
      }
      throw AppException('Não foi possível salvar o produto: $e');
    }
  }

  Future<bool> excluirProduto(int id) async {
    final db = await database;
    return db.transaction<bool>((txn) async {
      final usos = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM itens_venda WHERE produto_id = ?', [id])) ??
          0;
      if (usos > 0) {
        await txn.update('produtos', {'ativo': 0}, where: 'id = ?', whereArgs: [id]);
        return false;
      }
      await txn.delete('movimentacoes_estoque', where: 'produto_id = ?', whereArgs: [id]);
      await txn.delete('produtos', where: 'id = ?', whereArgs: [id]);
      return true;
    });
  }

  Future<void> reativarProduto(int id) async {
    final db = await database;
    await db.update('produtos', {'ativo': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Linha>> listarClientes({String busca = ''}) async {
    final db = await database;
    final b = '%${busca.trim()}%';
    return db.query(
      'clientes',
      where: busca.trim().isEmpty
          ? 'ativo = 1'
          : 'ativo = 1 AND (nome LIKE ? OR telefone LIKE ? OR email LIKE ?)',
      whereArgs: busca.trim().isEmpty ? null : [b, b, b],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<int> salvarCliente(Linha c, {int? id}) async {
    final nome = ((c['nome'] as String?) ?? '').trim();
    final tel = ((c['telefone'] as String?) ?? '').trim();
    final email = ((c['email'] as String?) ?? '').trim();
    final end = ((c['endereco'] as String?) ?? '').trim();
    if (nome.isEmpty) throw AppException('Informe o nome do cliente.');
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw AppException('E-mail inválido.');
    }
    final db = await database;
    final dup = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM clientes WHERE ativo = 1 AND lower(nome) = lower(?) AND IFNULL(telefone, '') = ? AND id != ?",
            [nome, tel, id ?? 0])) ??
        0;
    if (dup > 0) {
      throw AppException('Já existe um cliente com este nome e telefone.');
    }
    final Linha dados = {'nome': nome, 'telefone': tel, 'email': email, 'endereco': end};
    if (id == null) {
      dados['ativo'] = 1;
      return db.insert('clientes', dados);
    }
    await db.update('clientes', dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<bool> excluirCliente(int id) async {
    final db = await database;
    final vendas = Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM vendas WHERE cliente_id = ?', [id])) ??
        0;
    if (vendas > 0) {
      await db.update('clientes', {'ativo': 0}, where: 'id = ?', whereArgs: [id]);
      return false;
    }
    await db.delete('clientes', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  Future<void> reporEstoque(int produtoId, int qtd, String obs) async {
    if (qtd <= 0) throw AppException('Informe uma quantidade maior que zero.');
    final db = await database;
    await db.transaction<void>((txn) async {
      final n = await txn.rawUpdate(
          'UPDATE produtos SET quantidade = quantidade + ? WHERE id = ? AND ativo = 1',
          [qtd, produtoId]);
      if (n == 0) throw AppException('Produto não encontrado ou inativo.');
      await _mov(txn, produtoId, 'ENTRADA', qtd, obs.trim().isEmpty ? 'Reposição de estoque' : obs.trim());
    });
  }

  Future<List<Linha>> listarMovimentacoes() async {
    final db = await database;
    return db.rawQuery('''
SELECT m.id, m.tipo, m.quantidade, m.data_movimentacao, m.observacao, p.nome AS produto_nome
FROM movimentacoes_estoque m
JOIN produtos p ON p.id = m.produto_id
ORDER BY m.id DESC
LIMIT 100''');
  }

  Future<int> registrarVenda(int? clienteId, List<Linha> itens) async {
    if (clienteId == null) throw AppException('Selecione o cliente da venda.');
    if (itens.isEmpty) {
      throw AppException('Adicione ao menos um item à venda.'); // RN05
    }
    final qtds = <int, int>{};
    for (final i in itens) {
      final pid = i['produto_id'] as int;
      final q = i['quantidade'] as int;
      if (q <= 0) throw AppException('Quantidade inválida.');
      qtds[pid] = (qtds[pid] ?? 0) + q;
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final cli = await txn.query('clientes', where: 'id = ? AND ativo = 1', whereArgs: [clienteId]);
      if (cli.isEmpty) throw AppException('Cliente não encontrado ou inativo.');

      var total = 0.0;
      final linhas = <Linha>[];
      for (final e in qtds.entries) {
        final r = await txn.query('produtos', where: 'id = ?', whereArgs: [e.key]);
        if (r.isEmpty) throw AppException('Produto não encontrado.');
        final p = r.first;
        final nome = p['nome'] as String;
        if ((p['ativo'] as int) != 1) throw AppException('O produto "$nome" está inativo.');
        final disp = p['quantidade'] as int;
        if (e.value > disp) {
          throw AppException('Estoque insuficiente para "$nome". Disponível: $disp.'); // RN03
        }
        final preco = (p['preco_venda'] as num).toDouble();
        final sub = double.parse((preco * e.value).toStringAsFixed(2));
        total += sub;
        linhas.add({
          'produto_id': e.key,
          'quantidade': e.value,
          'preco_unitario': preco,
          'subtotal': sub,
        });
      }
      total = double.parse(total.toStringAsFixed(2)); // RN06

      final vendaId = await txn.insert('vendas', {
        'cliente_id': clienteId,
        'data_venda': DateTime.now().toIso8601String(),
        'valor_total': total,
        'status': 'CONFIRMADA',
      });
      for (final l in linhas) {
        final pid = l['produto_id'] as int;
        final q = l['quantidade'] as int;
        await txn.insert('itens_venda', {
          'venda_id': vendaId,
          'produto_id': pid,
          'quantidade': q,
          'preco_unitario': l['preco_unitario'],
          'subtotal': l['subtotal'],
        });
        await txn.rawUpdate('UPDATE produtos SET quantidade = quantidade - ? WHERE id = ?', [q, pid]);
        await _mov(txn, pid, 'SAIDA', q, 'Venda #$vendaId');
      }
      return vendaId;
    });
  }

  Future<void> cancelarVenda(int vendaId) async {
    final db = await database;
    await db.transaction<void>((txn) async {
      final v = await txn.query('vendas', where: 'id = ?', whereArgs: [vendaId]);
      if (v.isEmpty) throw AppException('Venda não encontrada.');
      if (v.first['status'] == 'CANCELADA') {
        throw AppException('Esta venda já foi cancelada.'); // RN11
      }
      final n = await txn.update(
        'vendas',
        {'status': 'CANCELADA'},
        where: "id = ? AND status = 'CONFIRMADA'",
        whereArgs: [vendaId],
      );
      if (n != 1) throw AppException('Esta venda já foi cancelada.');
      final itens = await txn.query('itens_venda', where: 'venda_id = ?', whereArgs: [vendaId]);
      for (final i in itens) {
        final pid = i['produto_id'] as int;
        final q = i['quantidade'] as int;
        await txn.rawUpdate('UPDATE produtos SET quantidade = quantidade + ? WHERE id = ?', [q, pid]);
        await _mov(txn, pid, 'CANCELAMENTO', q, 'Cancelamento da venda #$vendaId');
      }
    });
  }

  Future<List<Linha>> listarVendas({String? status}) async {
    final db = await database;
    final filtro = status == null ? '' : 'WHERE v.status = ?';
    return db.rawQuery('''
SELECT v.id, v.data_venda, v.valor_total, v.status, c.nome AS cliente_nome
FROM vendas v
JOIN clientes c ON c.id = v.cliente_id
$filtro
ORDER BY v.id DESC''', status == null ? null : [status]);
  }

  Future<List<Linha>> itensDaVenda(int vendaId) async {
    final db = await database;
    return db.rawQuery('''
SELECT i.quantidade, i.preco_unitario, i.subtotal, p.nome, p.codigo
FROM itens_venda i
JOIN produtos p ON p.id = i.produto_id
WHERE i.venda_id = ?
ORDER BY i.id''', [vendaId]);
  }

  Future<Map<String, num>> resumo() async {
    final db = await database;
    Future<int> contar(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;
    final fat = await db.rawQuery(
        "SELECT IFNULL(SUM(valor_total), 0) AS t FROM vendas WHERE status = 'CONFIRMADA'"); // RN12
    return {
      'produtos': await contar('SELECT COUNT(*) FROM produtos WHERE ativo = 1'),
      'clientes': await contar('SELECT COUNT(*) FROM clientes WHERE ativo = 1'),
      'vendas': await contar("SELECT COUNT(*) FROM vendas WHERE status = 'CONFIRMADA'"),
      'baixo': await contar('SELECT COUNT(*) FROM produtos WHERE ativo = 1 AND quantidade <= estoque_minimo'),
      'faturamento': (fat.first['t'] as num).toDouble(),
    };
  }

  Future<void> carregarExemplos() async {
    final db = await database;
    final np = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM produtos')) ?? 0;
    final nc = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM clientes')) ?? 0;
    if (np > 0 || nc > 0) {
      throw AppException('O banco já possui dados. Os exemplos só podem ser carregados com o banco vazio.');
    }
    final produtos = <List<Object>>[
      ['RC001', 'Ração Cães Adultos 15kg', 'Rações', 'NutriPet', 120.0, 169.9, 20, 5],
      ['RC002', 'Ração Cães Filhotes 10kg', 'Rações', 'NutriPet', 95.0, 139.9, 15, 4],
      ['RG001', 'Ração Gatos Adultos 10kg', 'Rações', 'GatoMax', 85.0, 124.9, 12, 4],
      ['RG002', 'Sachê Gatos Atum 85g', 'Rações', 'GatoMax', 1.8, 3.5, 100, 20],
      ['BR001', 'Bolinha de Borracha', 'Brinquedos', 'PetFun', 4.0, 9.9, 30, 8],
      ['BR002', 'Corda com Nó', 'Brinquedos', 'PetFun', 6.0, 14.9, 25, 6],
      ['BR003', 'Ratinho de Pelúcia', 'Brinquedos', 'PetFun', 3.5, 8.9, 40, 10],
      ['BR004', 'Mordedor Osso', 'Brinquedos', 'DogLife', 9.0, 22.9, 18, 5],
      ['AC001', 'Coleira Nylon M', 'Acessórios', 'DogLife', 12.0, 29.9, 22, 5],
      ['AC002', 'Guia Retrátil 5m', 'Acessórios', 'DogLife', 28.0, 64.9, 10, 3],
      ['AC003', 'Comedouro Inox', 'Acessórios', 'PetCasa', 10.0, 24.9, 16, 4],
      ['AC004', 'Caminha Média', 'Acessórios', 'PetCasa', 45.0, 99.9, 8, 2],
      ['HG001', 'Shampoo Neutro 500ml', 'Higiene', 'PetClean', 11.0, 27.9, 25, 6],
      ['HG002', 'Condicionador 500ml', 'Higiene', 'PetClean', 12.0, 29.9, 20, 5],
      ['HG003', 'Tapete Higiênico 30un', 'Higiene', 'PetClean', 35.0, 69.9, 14, 4],
      ['HG004', 'Areia Sanitária 4kg', 'Higiene', 'PetClean', 8.0, 19.9, 30, 8],
    ];
    for (final p in produtos) {
      await salvarProduto({
        'codigo': p[0],
        'nome': p[1],
        'categoria': p[2],
        'marca': p[3],
        'preco_custo': p[4],
        'preco_venda': p[5],
        'quantidade': p[6],
        'estoque_minimo': p[7],
      });
    }
    final clientes = <List<String>>[
      ['Ana Souza', '(31) 99111-1111', 'ana@email.com', 'Rua das Flores, 100 - Belo Horizonte'],
      ['Bruno Lima', '(31) 99222-2222', 'bruno@email.com', 'Av. Amazonas, 200 - Belo Horizonte'],
      ['Carla Mendes', '(31) 99333-3333', 'carla@email.com', 'Rua da Bahia, 300 - Belo Horizonte'],
      ['Diego Alves', '(31) 99444-4444', 'diego@email.com', 'Rua Sergipe, 400 - Belo Horizonte'],
      ['Elisa Rocha', '(31) 99555-5555', 'elisa@email.com', 'Av. Brasil, 500 - Belo Horizonte'],
    ];
    for (final c in clientes) {
      await salvarCliente({'nome': c[0], 'telefone': c[1], 'email': c[2], 'endereco': c[3]});
    }
  }
}
