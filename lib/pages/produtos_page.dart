import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  final _db = DatabaseHelper.instance;
  final _busca = TextEditingController();
  List<Linha> _produtos = [];
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
      final r = await _db.listarProdutos(busca: _busca.text);
      if (!mounted) return;
      setState(() {
        _produtos = r;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _abrirForm([Linha? produto]) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProdutoFormPage(produto: produto)),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _excluir(Linha p) async {
    final ok = await confirmar(
      context,
      'Excluir produto',
      'Deseja excluir "${p['nome']}"? Se ele já tiver vendas, será apenas inativado.',
    );
    if (!ok || !mounted) return;
    try {
      final fisico = await _db.excluirProduto(p['id'] as int);
      if (!mounted) return;
      mostrarMensagem(
        context,
        fisico ? 'Produto excluído com sucesso.' : 'Produto vinculado a vendas: foi inativado.',
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _reativar(Linha p) async {
    try {
      await _db.reativarProduto(p['id'] as int);
      if (!mounted) return;
      mostrarMensagem(context, 'Produto reativado.');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        icon: const Icon(Icons.add),
        label: const Text('Produto'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                labelText: 'Pesquisar produto',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _busca.clear();
                    _carregar();
                  },
                ),
              ),
              onChanged: (_) => _carregar(),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _produtos.isEmpty
                    ? const Center(child: Text('Nenhum produto encontrado.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: _produtos.length,
                        itemBuilder: (context, i) {
                          final p = _produtos[i];
                          final ativo = p['ativo'] == 1;
                          final qtd = p['quantidade'] as int;
                          final minimo = p['estoque_minimo'] as int;
                          final baixo = ativo && qtd <= minimo;
                          final marca = ((p['marca'] as String?) ?? '').trim();
                          final nome = ativo ? '${p['nome']}' : '${p['nome']} (inativo)';
                          final linha1 = [
                            'Cód: ${p['codigo']}',
                            '${p['categoria']}',
                            if (marca.isNotEmpty) marca,
                          ].join(' • ');
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              onTap: () => _abrirForm(p),
                              isThreeLine: true,
                              leading: Icon(
                                baixo ? Icons.warning_amber_rounded : Icons.pets,
                                color: baixo ? Colors.red : (ativo ? Colors.teal : Colors.grey),
                              ),
                              title: Text(nome),
                              subtitle: Text(
                                '$linha1\n'
                                'Custo: ${moeda(p['preco_custo'] as num)} • Venda: ${moeda(p['preco_venda'] as num)}\n'
                                'Estoque: $qtd (mín. $minimo)${baixo ? ' • ESTOQUE BAIXO' : ''}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'editar') _abrirForm(p);
                                  if (v == 'excluir') _excluir(p);
                                  if (v == 'reativar') _reativar(p);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'editar', child: Text('Editar')),
                                  if (ativo)
                                    const PopupMenuItem(value: 'excluir', child: Text('Excluir / inativar'))
                                  else
                                    const PopupMenuItem(value: 'reativar', child: Text('Reativar')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class ProdutoFormPage extends StatefulWidget {
  final Linha? produto;

  const ProdutoFormPage({super.key, this.produto});

  @override
  State<ProdutoFormPage> createState() => _ProdutoFormPageState();
}

class _ProdutoFormPageState extends State<ProdutoFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _nome = TextEditingController();
  final _marca = TextEditingController();
  final _custo = TextEditingController();
  final _venda = TextEditingController();
  final _qtd = TextEditingController(text: '0');
  final _minimo = TextEditingController(text: '0');
  String _categoria = categoriasProduto.first;
  bool _salvando = false;

  bool get _edicao => widget.produto != null;

  String _fmt(Object? v) => ((v as num?) ?? 0).toStringAsFixed(2).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    final p = widget.produto;
    if (p != null) {
      _codigo.text = '${p['codigo']}';
      _nome.text = '${p['nome']}';
      _marca.text = '${p['marca'] ?? ''}';
      _custo.text = _fmt(p['preco_custo']);
      _venda.text = _fmt(p['preco_venda']);
      _qtd.text = '${p['quantidade']}';
      _minimo.text = '${p['estoque_minimo']}';
      _categoria = '${p['categoria']}';
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nome.dispose();
    _marca.dispose();
    _custo.dispose();
    _venda.dispose();
    _qtd.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final custo = lerDouble(_custo.text)!;
    final venda = lerDouble(_venda.text)!;
    String? justificativa;
    if (venda < custo) {
      // RN10: confirmação e justificativa para preço abaixo do custo.
      final ok = await confirmar(
        context,
        'Preço abaixo do custo',
        'O preço de venda (${moeda(venda)}) é menor que o custo (${moeda(custo)}). Deseja continuar?',
      );
      if (!ok || !mounted) return;
      justificativa = await pedirJustificativa(context);
      if (justificativa == null || !mounted) return;
    }
    setState(() => _salvando = true);
    try {
      await DatabaseHelper.instance.salvarProduto(
        {
          'codigo': _codigo.text,
          'nome': _nome.text,
          'categoria': _categoria,
          'marca': _marca.text,
          'preco_custo': custo,
          'preco_venda': venda,
          'quantidade': lerInt(_qtd.text) ?? 0,
          'estoque_minimo': lerInt(_minimo.text) ?? 0,
          'justificativa_preco': justificativa,
        },
        id: widget.produto?['id'] as int?,
      );
      if (!mounted) return;
      mostrarMensagem(context, 'Produto salvo com sucesso!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categorias = <String>{...categoriasProduto, _categoria}.toList();
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(title: Text(_edicao ? 'Editar produto' : 'Novo produto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _codigo,
              decoration: const InputDecoration(labelText: 'Código *'),
              validator: obrigatorio('Informe o código'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: obrigatorio('Informe o nome do produto'),
            ),
            const SizedBox(height: 12),
            campoDropdown<String>(
              rotulo: 'Categoria *',
              valor: _categoria,
              itens: categorias
                  .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                  .toList(),
              aoMudar: (v) => setState(() => _categoria = v ?? _categoria),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _marca,
              decoration: const InputDecoration(labelText: 'Marca'),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _custo,
                    keyboardType: decimal,
                    decoration: const InputDecoration(labelText: 'Preço de custo *', prefixText: 'R\$ '),
                    validator: validarPreco,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _venda,
                    keyboardType: decimal,
                    decoration: const InputDecoration(labelText: 'Preço de venda *', prefixText: 'R\$ '),
                    validator: validarPreco,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtd,
                    enabled: !_edicao,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantidade *',
                      helperText: _edicao ? 'Altere em Estoque > Repor' : null,
                    ),
                    validator: validarInteiro,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minimo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Estoque mínimo *'),
                    validator: validarInteiro,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save),
              label: Text(_salvando ? 'Salvando...' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
