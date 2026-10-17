import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

/// Nova venda: cliente, múltiplos itens, quantidades e totalização.
class VendasPage extends StatefulWidget {
  const VendasPage({super.key});

  @override
  State<VendasPage> createState() => _VendasPageState();
}

class _VendasPageState extends State<VendasPage> {
  final _db = DatabaseHelper.instance;
  final _qtd = TextEditingController(text: '1');
  List<Linha> _clientes = [];
  List<Linha> _produtos = [];
  final List<Linha> _carrinho = [];
  int? _clienteId;
  int? _produtoId;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _qtd.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final c = await _db.listarClientes();
      final p = await _db.listarProdutos(apenasAtivos: true);
      if (!mounted) return;
      setState(() {
        _clientes = c;
        _produtos = p;
        if (!_clientes.any((e) => e['id'] == _clienteId)) _clienteId = null;
        if (!_produtos.any((e) => e['id'] == _produtoId)) _produtoId = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  double _subtotal(Linha i) => (i['preco'] as double) * (i['quantidade'] as int);

  double get _total => _carrinho.fold<double>(0, (soma, i) => soma + _subtotal(i));

  void _adicionar() {
    final id = _produtoId;
    final q = lerInt(_qtd.text);
    if (id == null) {
      mostrarMensagem(context, 'Selecione um produto.', erro: true);
      return;
    }
    if (q == null || q <= 0) {
      mostrarMensagem(context, 'Informe uma quantidade válida.', erro: true);
      return;
    }
    final p = _produtos.firstWhere((e) => e['id'] == id);
    final disp = p['quantidade'] as int;
    final idx = _carrinho.indexWhere((i) => i['produto_id'] == id);
    final jaNoCarrinho = idx >= 0 ? _carrinho[idx]['quantidade'] as int : 0;
    // RN03: não permite vender mais do que o estoque disponível.
    if (q + jaNoCarrinho > disp) {
      mostrarMensagem(
        context,
        'Estoque insuficiente para "${p['nome']}". Disponível: $disp (já no carrinho: $jaNoCarrinho).',
        erro: true,
      );
      return;
    }
    setState(() {
      if (idx >= 0) {
        _carrinho[idx]['quantidade'] = jaNoCarrinho + q;
      } else {
        _carrinho.add({
          'produto_id': id,
          'nome': p['nome'],
          'preco': (p['preco_venda'] as num).toDouble(),
          'quantidade': q,
        });
      }
      _qtd.text = '1';
    });
  }

  Future<void> _confirmarVenda() async {
    if (_clienteId == null) {
      mostrarMensagem(context, 'Selecione o cliente da venda.', erro: true);
      return;
    }
    if (_carrinho.isEmpty) {
      mostrarMensagem(context, 'Adicione ao menos um item à venda.', erro: true); // RN05
      return;
    }
    final ok = await confirmar(
      context,
      'Confirmar venda',
      'Total da venda: ${moeda(_total)}. Deseja confirmar?',
    );
    if (!ok || !mounted) return;
    setState(() => _salvando = true);
    try {
      final itens = _carrinho
          .map((i) => <String, Object?>{
                'produto_id': i['produto_id'],
                'quantidade': i['quantidade'],
              })
          .toList();
      final total = _total;
      final id = await _db.registrarVenda(_clienteId, itens);
      if (!mounted) return;
      _carrinho.clear();
      _clienteId = null;
      _produtoId = null;
      setState(() => _salvando = false);
      mostrarMensagem(context, 'Venda #$id confirmada com sucesso! Total: ${moeda(total)}');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
      await _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_clientes.isEmpty || _produtos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Para registrar vendas, cadastre ao menos um cliente e um produto '
            '(ou carregue os dados de exemplo no Dashboard).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        campoDropdown<int>(
          rotulo: 'Cliente *',
          valor: _clienteId,
          itens: _clientes
              .map((c) => DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text('${c['nome']}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          aoMudar: (v) => setState(() => _clienteId = v),
        ),
        const SizedBox(height: 12),
        campoDropdown<int>(
          rotulo: 'Produto',
          valor: _produtoId,
          itens: _produtos
              .map((p) => DropdownMenuItem<int>(
                    value: p['id'] as int,
                    child: Text(
                      '${p['nome']} • ${moeda(p['preco_venda'] as num)} • est.: ${p['quantidade']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          aoMudar: (v) => setState(() => _produtoId = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qtd,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantidade'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _adicionar,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Adicionar'),
            ),
          ],
        ),
        const Divider(height: 32),
        const Text('Itens da venda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (_carrinho.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nenhum item adicionado.'),
          ),
        for (var n = 0; n < _carrinho.length; n++)
          Card(
            child: ListTile(
              title: Text('${_carrinho[n]['nome']}'),
              subtitle: Text(
                '${_carrinho[n]['quantidade']} x ${moeda(_carrinho[n]['preco'] as double)}'
                ' = ${moeda(_subtotal(_carrinho[n]))}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => _carrinho.removeAt(n)),
              ),
            ),
          ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              moeda(_total),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _salvando ? null : _confirmarVenda,
          icon: const Icon(Icons.check_circle),
          label: Text(_salvando ? 'Registrando...' : 'Confirmar venda'),
        ),
      ],
    );
  }
}
