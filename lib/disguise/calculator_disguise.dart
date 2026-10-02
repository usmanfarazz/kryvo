import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// "Calculator" disguise: a real, working calculator. Typing the secret code
/// (or the PIN) on its own and pressing = opens the vault.
class CalculatorDisguise extends StatefulWidget {
  const CalculatorDisguise({super.key});

  @override
  State<CalculatorDisguise> createState() => _CalculatorDisguiseState();
}

class _CalculatorDisguiseState extends State<CalculatorDisguise> {
  static const _bg = Color(0xFF000000);
  static const _num = Color(0xFF333333);
  static const _fn = Color(0xFFA5A5A5);
  static const _op = Color(0xFFFF9F0A);

  String _expr = '';
  String _result = '';
  bool _justEvaluated = false;

  void _press(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (k) {
        case 'AC':
          _expr = '';
          _result = '';
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
          _result = _preview();
        case '=':
          _equals();
          return;
        case '±':
          _toggleSign();
          _result = _preview();
        default:
          final isOp = '+−×÷%'.contains(k);
          if (_justEvaluated && !isOp) _expr = '';
          if (isOp) {
            if (_expr.isEmpty) {
              if (k != '−') return;
            } else if ('+−×÷%'.contains(_expr[_expr.length - 1])) {
              _expr = _expr.substring(0, _expr.length - 1);
            }
          }
          if (k == '.') {
            final last = RegExp(r'[\d.]*$').stringMatch(_expr) ?? '';
            if (last.contains('.')) return;
            if (last.isEmpty) _expr += '0';
          }
          _expr += k;
          _result = _preview();
      }
      _justEvaluated = false;
    });
  }

  void _toggleSign() {
    final m = RegExp(r'(−?)([\d.]+)$').firstMatch(_expr);
    if (m == null) return;
    final start = m.start;
    final neg = m.group(1)!.isNotEmpty;
    // Only treat a leading "−" as a sign (not as minus between two numbers).
    final isSign = neg && (start == 0 || '+−×÷%'.contains(_expr[start - 1]));
    _expr = isSign
        ? _expr.substring(0, start) + m.group(2)!
        : '${_expr.substring(0, start + m.group(1)!.length)}−${m.group(2)!}';
  }

  String _preview() {
    if (!RegExp(r'[+−×÷%]').hasMatch(_expr.replaceFirst(RegExp(r'^−'), ''))) {
      return '';
    }
    final v = CalcEngine.eval(_expr);
    return v == null ? '' : CalcEngine.format(v);
  }

  Future<void> _equals() async {
    final entry = _expr;
    // A plain number on its own may be the secret code / PIN.
    if (RegExp(r'^\d{4,8}$').hasMatch(entry)) {
      final app = context.read<AppState>();
      if (await app.tryDisguiseCode(entry)) {
        if (mounted) setState(() => _expr = _result = '');
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      final v = CalcEngine.eval(entry);
      if (v == null) {
        _result = entry.isEmpty ? '' : 'Error';
      } else {
        _expr = CalcEngine.format(v);
        _result = '';
      }
      _justEvaluated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['AC', '±', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['⌫', '0', '.', '='],
    ];
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_expr.isEmpty ? '0' : _expr,
                            maxLines: 1,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 64,
                                fontWeight: FontWeight.w300)),
                      ),
                      const SizedBox(height: 4),
                      Text(_result,
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 28)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [for (final k in row) _key(k)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(String k) {
    final isOp = '÷×−+='.contains(k);
    final isFn = k == 'AC' || k == '±' || k == '%';
    final color = isOp ? _op : (isFn ? _fn : _num);
    final fg = isFn ? Colors.black : Colors.white;
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _press(k),
          child: Center(
            child: k == '⌫'
                ? Icon(Icons.backspace_outlined, color: fg, size: 26)
                : Text(k,
                    style: TextStyle(
                        color: fg,
                        fontSize: isFn ? 26 : 32,
                        fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

/// Tiny expression evaluator: + − × ÷ % with normal precedence (public so
/// it can be unit-tested).
class CalcEngine {
  static double? eval(String expr) {
    if (expr.isEmpty) return null;
    var s = expr;
    while (s.isNotEmpty && '+−×÷'.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    final tokens = <String>[];
    var num = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      final unaryMinus =
          c == '−' && (i == 0 || '+−×÷'.contains(s[i - 1])) && num.isEmpty;
      if ('0123456789.'.contains(c) || unaryMinus) {
        num += c == '−' ? '-' : c;
      } else if (c == '%') {
        if (num.isEmpty) return null;
        num = '${(double.tryParse(num) ?? 0) / 100}';
      } else {
        if (num.isEmpty) return null;
        tokens
          ..add(num)
          ..add(c);
        num = '';
      }
    }
    if (num.isEmpty) return null;
    tokens.add(num);

    // × and ÷ first
    final stack = <String>[tokens.first];
    for (var i = 1; i < tokens.length; i += 2) {
      final op = tokens[i];
      final b = double.tryParse(tokens[i + 1]);
      if (b == null) return null;
      if (op == '×' || op == '÷') {
        final a = double.tryParse(stack.removeLast());
        if (a == null) return null;
        if (op == '÷' && b == 0) return null;
        stack.add('${op == '×' ? a * b : a / b}');
      } else {
        stack
          ..add(op)
          ..add('$b');
      }
    }
    var total = double.tryParse(stack.first);
    if (total == null) return null;
    for (var i = 1; i < stack.length; i += 2) {
      final b = double.tryParse(stack[i + 1]);
      if (b == null) return null;
      total = stack[i] == '+' ? total! + b : total! - b;
    }
    return total;
  }

  static String format(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString().replaceFirst('-', '−');
    }
    var s = v.toStringAsPrecision(10);
    if (s.contains('.') && !s.contains('e')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s.replaceFirst('-', '−');
  }
}
