import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/utils/coercion_handler.dart';

/// A functional calculator that serves as a disguise for the real app.
/// Typing the coercion PIN followed by '=' unlocks the real app.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _currentInput = '';
  String _operator = '';
  double _firstOperand = 0;
  bool _shouldResetDisplay = false;
  // Track digit sequence for PIN detection.
  String _digitSequence = '';

  void _onDigit(String digit) {
    setState(() {
      if (_shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        _display = _display == '0' ? digit : _display + digit;
      }
      _currentInput += digit;
      _digitSequence += digit;
    });
  }

  void _onOperator(String op) {
    setState(() {
      _firstOperand = double.tryParse(_display) ?? 0;
      _operator = op;
      _shouldResetDisplay = true;
      _currentInput = '';
    });
  }

  void _onEquals() async {
    // Check if the digit sequence contains the PIN.
    final coercionHandler = context.read<CoercionHandler>();
    final hasPin = await coercionHandler.hasCoercionPin();

    if (hasPin && _digitSequence.length >= 4) {
      // Check last N digits as potential PIN.
      for (var len = 4; len <= _digitSequence.length && len <= 8; len++) {
        final candidate = _digitSequence.substring(_digitSequence.length - len);
        final isPin = await coercionHandler.isCoercionPin(candidate);
        if (isPin) {
          if (mounted) context.go('/home');
          return;
        }
      }
    }

    // Normal calculator operation.
    setState(() {
      final secondOperand = double.tryParse(_display) ?? 0;
      double result = 0;

      switch (_operator) {
        case '+': result = _firstOperand + secondOperand; break;
        case '-': result = _firstOperand - secondOperand; break;
        case '*': result = _firstOperand * secondOperand; break;
        case '/':
          result = secondOperand != 0 ? _firstOperand / secondOperand : 0;
          break;
        default: result = secondOperand;
      }

      _display = result == result.truncateToDouble()
          ? result.truncate().toString()
          : result.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
      _operator = '';
      _currentInput = '';
      _shouldResetDisplay = true;
      _digitSequence = '';
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _currentInput = '';
      _operator = '';
      _firstOperand = 0;
      _shouldResetDisplay = false;
      _digitSequence = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Display
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.all(24),
                child: Text(
                  _display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Buttons
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _buildRow(['C', '±', '%', '÷']),
                  _buildRow(['7', '8', '9', '×']),
                  _buildRow(['4', '5', '6', '-']),
                  _buildRow(['1', '2', '3', '+']),
                  _buildRow(['0', '.', '=']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> buttons) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons.map((btn) {
          final isOperator = ['÷', '×', '-', '+', '='].contains(btn);
          final isSpecial = ['C', '±', '%'].contains(btn);
          final isZero = btn == '0';

          return Expanded(
            flex: isZero ? 2 : 1,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: MaterialButton(
                color: isOperator
                    ? Colors.orange
                    : isSpecial
                        ? Colors.grey[700]
                        : Colors.grey[850],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                onPressed: () {
                  if (btn == 'C') _onClear();
                  else if (btn == '=') _onEquals();
                  else if (btn == '+') _onOperator('+');
                  else if (btn == '-') _onOperator('-');
                  else if (btn == '×') _onOperator('*');
                  else if (btn == '÷') _onOperator('/');
                  else if (btn == '±') {
                    setState(() {
                      if (_display.startsWith('-')) {
                        _display = _display.substring(1);
                      } else if (_display != '0') {
                        _display = '-$_display';
                      }
                    });
                  }
                  else if (btn == '%') {
                    setState(() {
                      final val = (double.tryParse(_display) ?? 0) / 100;
                      _display = val.toString();
                    });
                  }
                  else {
                    _onDigit(btn);
                  }
                },
                child: Text(
                  btn,
                  style: TextStyle(
                    color: isSpecial ? Colors.black : Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
