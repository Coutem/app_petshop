import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

class _Reposicao {
  final int qtd;
  final String obs;
  _Reposicao(this.qtd, this.obs);
}

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final _db = DatabaseHelper.instance;
  final _busca = TextEditingController();
  List<Linha> _produtos = [];
  List<Linha> _movs = [];
  bool _somenteAlertas = false;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final p = await _db.listarProdutos(busca: _busca.text, apenasAtivos: true);
      final m = await _db.listarMovimentacoes();
      if (!mounted) return;
      setState(() {
        _produtos = p;
        _movs = m;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  bool _baixo(Linha p) => (p['quantidade'] as int) <= (p['estoque_minimo'] as int);

  Future<void> _repor(Linha p) async {
    final dados = await showDialog<_Reposicao>(
      context: context,
      builder: (_) => _ReporDialog('${p['nome']}'),
    );
    if (dados == null || !mounted) return;
    try {
      await _db.reporEstoque(p['id'] as int, dados.qtd, dados.obs);
      if (!mounted) return;
      mostrarMensagem(context, 'Reposição de ${dados.qtd} unidade(s) registrada com sucesso!');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Widget _saldos() {
    final lista = _somenteAlertas ? _produtos.where(_baixo).toList() : _produtos;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _busca,
            decoration: const InputDecoration(
              labelText: 'Pesquisar produto',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _carregar(),
          ),
        ),
        SwitchListTile(
          title: const Text('Mostrar somente alertas'),
          value: _somenteAlertas,
          onChanged: (v) => setState(() => _somenteAlertas = v),
        ),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : lista.isEmpty
                  ? const Center(child: Text('Nenhum produto encontrado.'))
                  : ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (context, i) {
                        final p = lista[i];
                        final baixo = _baixo(p);
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              baixo ? Icons.warning_amber_rounded : Icons.check_circle,
                              color: baixo ? Colors.red : Colors.green,
                            ),
                            title: Text('${p['nome']}'),
                            subtitle: Text(
                              'Saldo: ${p['quantidade']} • Mínimo: ${p['estoque_minimo']}'
                              '${baixo ? '\nESTOQUE BAIXO' : ''}',
                              style: TextStyle(color: baixo ? Colors.red.shade700 : null),
                            ),
                            isThreeLine: baixo,
                            trailing: FilledButton.tonal(
                              onPressed: () => _repor(p),
                              child: const Text('Repor'),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _movimentacoes() {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_movs.isEmpty) return const Center(child: Text('Nenhuma movimentação registrada.'));
    return ListView.builder(
      itemCount: _movs.length,
      itemBuilder: (context, i) {
        final m = _movs[i];
        final tipo = '${m['tipo']}';
        final entrada = tipo == 'ENTRADA';
        final saida = tipo == 'SAIDA';
        final rotulo = entrada ? 'Entrada' : (saida ? 'Saída' : 'Estorno');
        return ListTile(
          leading: Icon(
            entrada ? Icons.arrow_downward : (saida ? Icons.arrow_upward : Icons.undo),
            color: saida ? Colors.red : Colors.green,
          ),
          title: Text('${m['produto_nome']}'),
          subtitle: Text(
            '$rotulo de ${m['quantidade']} • ${dataHora('${m['data_movimentacao']}')}\n'
            '${m['observacao'] ?? ''}',
          ),
          isThreeLine: true,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Saldos'),
              Tab(text: 'Movimentações'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _saldos(),
                _movimentacoes(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReporDialog extends StatefulWidget {
  final String produto;

  const _ReporDialog(this.produto);

  @override
  State<_ReporDialog> createState() => _ReporDialogState();
}

class _ReporDialogState extends State<_ReporDialog> {
  final _qtd = TextEditingController();
  final _obs = TextEditingController(text: 'Reposição de estoque');
  String? _erro;

  @override
  void dispose() {
    _qtd.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Repor estoque'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.produto, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _qtd,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Quantidade a repor', errorText: _erro),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              decoration: const InputDecoration(labelText: 'Observação'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final q = lerInt(_qtd.text);
            if (q == null || q <= 0) {
              setState(() => _erro = 'Informe um número maior que zero');
              return;
            }
            Navigator.pop(context, _Reposicao(q, _obs.text));
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
